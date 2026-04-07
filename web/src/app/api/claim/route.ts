import { NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db";
import { retrieveBillingCheckout } from "@/lib/airwallex";
import { generateAccessToken, hashToken } from "@/lib/tokens";
import { syncSubscriptionFromAirwallex, upsertCustomerByEmail } from "@/lib/subscription-sync";

export const runtime = "nodejs";

const bodySchema = z.object({
  checkoutId: z.string().min(8),
});

function checkoutComplete(status: unknown): boolean {
  const s = String(status ?? "").toUpperCase();
  return s === "COMPLETED" || s === "COMPLETE" || s === "SUCCEEDED" || s === "PAID";
}

function extractEmail(checkout: Record<string, unknown>): string | undefined {
  const cd = checkout.customer_data as Record<string, unknown> | undefined;
  const emailFromCd = cd && typeof cd.email === "string" ? cd.email : undefined;
  if (emailFromCd) {
    return emailFromCd;
  }
  const cust = checkout.customer as Record<string, unknown> | undefined;
  if (cust && typeof cust.email === "string") {
    return cust.email;
  }
  return undefined;
}

function extractBillingCustomerId(checkout: Record<string, unknown>): string | undefined {
  const cust = checkout.customer as Record<string, unknown> | undefined;
  if (cust && typeof cust.id === "string") {
    return cust.id;
  }
  const id = checkout.billing_customer_id ?? checkout.billingCustomerId;
  return typeof id === "string" ? id : undefined;
}

export async function POST(req: Request) {
  try {
    const json = await req.json();
    const { checkoutId } = bodySchema.parse(json);

    const checkout = await retrieveBillingCheckout(checkoutId);
    if (!checkoutComplete(checkout.status)) {
      return NextResponse.json(
        { error: "Checkout is not completed yet", status: checkout.status },
        { status: 409 },
      );
    }

    const email = extractEmail(checkout);
    if (!email) {
      return NextResponse.json({ error: "Could not read customer email from checkout" }, { status: 422 });
    }

    const billingCustomerId = extractBillingCustomerId(checkout);
    const customer = await upsertCustomerByEmail(email, billingCustomerId);

    const subIdRaw = checkout.subscription_id ?? checkout.subscriptionId;
    const subscriptionId = typeof subIdRaw === "string" ? subIdRaw : undefined;
    if (subscriptionId) {
      await syncSubscriptionFromAirwallex(customer.id, subscriptionId);
    }

    const plaintext = generateAccessToken();
    const tokenHash = hashToken(plaintext);

    await prisma.$transaction(async (tx) => {
      await tx.checkoutClaim.upsert({
        where: { checkoutId },
        create: { checkoutId, customerId: customer.id },
        update: {},
      });

      await tx.accessToken.updateMany({
        where: { customerId: customer.id, revokedAt: null },
        data: { revokedAt: new Date() },
      });

      await tx.accessToken.create({
        data: { customerId: customer.id, tokenHash },
      });
    });

    return NextResponse.json({
      accessToken: plaintext,
      email: customer.email,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    if (e instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
    }
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
