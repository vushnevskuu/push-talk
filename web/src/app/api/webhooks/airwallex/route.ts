import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { verifyAirwallexWebhook } from "@/lib/webhook-verify";
import { syncSubscriptionFromAirwallex, upsertCustomerByEmail } from "@/lib/subscription-sync";

export const runtime = "nodejs";

function deepFindSubscriptionId(obj: unknown): string | undefined {
  if (!obj || typeof obj !== "object") {
    return undefined;
  }
  const rec = obj as Record<string, unknown>;
  const direct = rec.subscription_id ?? rec.subscriptionId;
  if (typeof direct === "string") {
    return direct;
  }
  const data = rec.data;
  if (data && typeof data === "object") {
    const inner = deepFindSubscriptionId(data);
    if (inner) {
      return inner;
    }
  }
  const object = rec.object;
  if (object && typeof object === "object") {
    return deepFindSubscriptionId(object);
  }
  return undefined;
}

function deepFindEmail(obj: unknown): string | undefined {
  if (!obj || typeof obj !== "object") {
    return undefined;
  }
  const rec = obj as Record<string, unknown>;
  if (typeof rec.email === "string") {
    return rec.email;
  }
  const customer = rec.customer;
  if (customer && typeof customer === "object") {
    const e = (customer as Record<string, unknown>).email;
    if (typeof e === "string") {
      return e;
    }
  }
  const data = rec.data;
  if (data) {
    return deepFindEmail(data);
  }
  return undefined;
}

export async function POST(req: Request) {
  const rawBody = await req.text();
  const sig = req.headers.get("x-signature") ?? req.headers.get("x-airwallex-signature");

  if (!verifyAirwallexWebhook(rawBody, sig)) {
    return NextResponse.json({ error: "invalid signature" }, { status: 401 });
  }

  let payload: unknown;
  try {
    payload = JSON.parse(rawBody) as unknown;
  } catch {
    return NextResponse.json({ error: "invalid json" }, { status: 400 });
  }

  const subscriptionId = deepFindSubscriptionId(payload);
  const email = deepFindEmail(payload);

  if (subscriptionId && email) {
    try {
      const customer = await upsertCustomerByEmail(email);
      await syncSubscriptionFromAirwallex(customer.id, subscriptionId);
    } catch (e) {
      console.error("webhook sync failed", e);
    }
  }

  return NextResponse.json({ received: true });
}
