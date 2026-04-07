import { NextResponse } from "next/server";
import { prisma } from "@/lib/db";
import { hashToken } from "@/lib/tokens";
import { subscriptionAllowsAccess, syncSubscriptionFromAirwallex } from "@/lib/subscription-sync";

export const runtime = "nodejs";

export async function GET(req: Request) {
  try {
    const auth = req.headers.get("authorization") ?? "";
    const m = auth.match(/^Bearer\s+(.+)$/i);
    const raw = m?.[1]?.trim();
    if (!raw) {
      return NextResponse.json({ ok: false, error: "missing_bearer" }, { status: 401 });
    }

    const tokenHash = hashToken(raw);
    const row = await prisma.accessToken.findFirst({
      where: { tokenHash, revokedAt: null },
      include: {
        customer: {
          include: {
            subscriptions: { orderBy: { updatedAt: "desc" }, take: 1 },
          },
        },
      },
    });

    if (!row) {
      return NextResponse.json({ ok: false, error: "invalid_token" }, { status: 401 });
    }

    await prisma.accessToken.update({
      where: { id: row.id },
      data: { lastUsedAt: new Date() },
    });

    let sub = row.customer.subscriptions[0];
    if (sub?.airwallexSubId) {
      try {
        await syncSubscriptionFromAirwallex(row.customerId, sub.airwallexSubId);
        sub =
          (await prisma.subscription.findFirst({
            where: { customerId: row.customerId },
            orderBy: { updatedAt: "desc" },
          })) ?? sub;
      } catch {
        /* offline grace: use cached row */
      }
    }

    if (!sub) {
      return NextResponse.json({
        ok: false,
        error: "no_subscription",
        email: row.customer.email,
      });
    }

    const allowed = subscriptionAllowsAccess(sub.status);
    return NextResponse.json({
      ok: allowed,
      status: sub.status,
      trialEndsAt: sub.trialEndsAt?.toISOString() ?? null,
      currentPeriodEnd: sub.currentPeriodEnd?.toISOString() ?? null,
      cancelAtPeriodEnd: sub.cancelAtPeriodEnd,
      email: row.customer.email,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    return NextResponse.json({ ok: false, error: message }, { status: 500 });
  }
}
