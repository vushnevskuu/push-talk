import { prisma } from "@/lib/db";
import { retrieveSubscription } from "@/lib/airwallex";

function pickString(obj: Record<string, unknown>, keys: string[]): string | undefined {
  for (const k of keys) {
    const v = obj[k];
    if (typeof v === "string" && v.length > 0) {
      return v;
    }
  }
  return undefined;
}

function pickDate(obj: Record<string, unknown>, keys: string[]): Date | undefined {
  const s = pickString(obj, keys);
  if (!s) {
    return undefined;
  }
  const t = Date.parse(s);
  return Number.isNaN(t) ? undefined : new Date(t);
}

export async function upsertCustomerByEmail(email: string, billingCustomerId?: string) {
  const normalized = email.trim().toLowerCase();
  return prisma.customer.upsert({
    where: { email: normalized },
    create: {
      email: normalized,
      airwallexBillingCustomerId: billingCustomerId,
    },
    update: {
      ...(billingCustomerId ? { airwallexBillingCustomerId: billingCustomerId } : {}),
    },
  });
}

export async function syncSubscriptionFromAirwallex(
  customerId: string,
  subscriptionId: string,
): Promise<void> {
  const sub = await retrieveSubscription(subscriptionId);
  const status = pickString(sub, ["status"]) ?? "UNKNOWN";
  const trialEndsAt = pickDate(sub, ["trial_ends_at", "trialEndsAt"]);
  const currentPeriodEnd = pickDate(sub, ["current_period_ends_at", "currentPeriodEndsAt", "current_period_end"]);

  await prisma.subscription.upsert({
    where: { airwallexSubId: subscriptionId },
    create: {
      customerId,
      airwallexSubId: subscriptionId,
      status,
      trialEndsAt: trialEndsAt ?? null,
      currentPeriodEnd: currentPeriodEnd ?? null,
      cancelAtPeriodEnd: Boolean(sub.cancel_at_period_end ?? sub.cancelAtPeriodEnd),
    },
    update: {
      status,
      trialEndsAt: trialEndsAt ?? null,
      currentPeriodEnd: currentPeriodEnd ?? null,
      cancelAtPeriodEnd: Boolean(sub.cancel_at_period_end ?? sub.cancelAtPeriodEnd),
    },
  });
}

export function subscriptionAllowsAccess(status: string): boolean {
  const s = status.toUpperCase();
  return s === "IN_TRIAL" || s === "ACTIVE";
}
