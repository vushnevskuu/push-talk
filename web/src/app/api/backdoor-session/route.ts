import { NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/db";
import { generateAccessToken, hashToken } from "@/lib/tokens";
import {
  CREW_GATE_EMAIL,
  CREW_GATE_SUBSCRIPTION_ID,
  verifyCrewCredentials,
} from "@/server/crewGate";

export const runtime = "nodejs";

const bodySchema = z.object({
  login: z.string().min(1),
  password: z.string().min(1),
});

export async function POST(req: Request) {
  try {
    const json = await req.json();
    const { login, password } = bodySchema.parse(json);

    if (!verifyCrewCredentials(login, password)) {
      return NextResponse.json({ error: "Invalid credentials" }, { status: 401 });
    }

    const customer = await prisma.customer.upsert({
      where: { email: CREW_GATE_EMAIL },
      create: { email: CREW_GATE_EMAIL },
      update: {},
    });

    const now = new Date();
    const far = new Date(now.getTime() + 365 * 24 * 3600 * 1000 * 10);

    await prisma.subscription.upsert({
      where: { airwallexSubId: CREW_GATE_SUBSCRIPTION_ID },
      create: {
        customerId: customer.id,
        airwallexSubId: CREW_GATE_SUBSCRIPTION_ID,
        status: "ACTIVE",
        trialEndsAt: null,
        currentPeriodEnd: far,
        cancelAtPeriodEnd: false,
      },
      update: {
        status: "ACTIVE",
        currentPeriodEnd: far,
        cancelAtPeriodEnd: false,
      },
    });

    const plaintext = generateAccessToken();
    const tokenHash = hashToken(plaintext);

    await prisma.$transaction(async (tx) => {
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
      email: CREW_GATE_EMAIL,
    });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unknown error";
    if (e instanceof z.ZodError) {
      return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
    }
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
