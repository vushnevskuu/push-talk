import { randomUUID } from "crypto";
import { NextResponse } from "next/server";
import { z } from "zod";
import { createBillingCheckout } from "@/lib/airwallex";

export const runtime = "nodejs";

const bodySchema = z.object({
  email: z.string().email(),
});

export async function POST(req: Request) {
  try {
    const json = await req.json();
    const { email } = bodySchema.parse(json);

    const appUrl = process.env.NEXT_PUBLIC_APP_URL?.replace(/\/$/, "");
    if (!appUrl) {
      return NextResponse.json({ error: "NEXT_PUBLIC_APP_URL is not configured" }, { status: 500 });
    }

    const legalEntityId = process.env.AIRWALLEX_LEGAL_ENTITY_ID;
    const linkedPaymentAccountId = process.env.AIRWALLEX_LINKED_PAYMENT_ACCOUNT_ID;
    const recurringPriceId = process.env.AIRWALLEX_RECURRING_PRICE_ID;
    const setupPriceId = process.env.AIRWALLEX_TRIAL_SETUP_PRICE_ID;

    if (!legalEntityId || !linkedPaymentAccountId || !recurringPriceId) {
      return NextResponse.json(
        { error: "Missing Airwallex billing env (legal entity, linked account, recurring price)" },
        { status: 500 },
      );
    }

    const trialEndsAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

    const lineItems: { price_id: string; quantity: number }[] = [
      { price_id: recurringPriceId, quantity: 1 },
    ];
    if (setupPriceId) {
      lineItems.push({ price_id: setupPriceId, quantity: 1 });
    }

    const payload: Record<string, unknown> = {
      request_id: randomUUID(),
      mode: "SUBSCRIPTION",
      legal_entity_id: legalEntityId,
      linked_payment_account_id: linkedPaymentAccountId,
      success_url: `${appUrl}/success`,
      back_url: appUrl,
      customer_data: {
        email: email.trim().toLowerCase(),
      },
      line_items: lineItems,
      subscription_data: {
        trial_ends_at: trialEndsAt,
        duration: { period: 1, period_unit: "MONTH" },
        days_until_due: 0,
      },
    };

    const created = (await createBillingCheckout(payload)) as Record<string, unknown>;
    const url = created.url ?? created.checkout_url;
    const id = created.id;

    if (typeof url !== "string" || typeof id !== "string") {
      return NextResponse.json(
        { error: "Unexpected Airwallex response (missing checkout URL)", raw: created },
        { status: 502 },
      );
    }

    return NextResponse.json({ url, checkoutId: id });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    if (e instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid email", details: e.flatten() }, { status: 400 });
    }
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
