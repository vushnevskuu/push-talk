import { WHISPER_STAR_PATH } from "@/lib/whisperStarPath";

/** Декоративные угловые завитки (бордо). */

/** Угловой индекс карты: звезда (из star.svg) + штрихи — по бокам от главного заголовка. */
export function ImpHeroFlank({ flip = false }: { flip?: boolean }) {
  return (
    <svg
      className={`imp-hero-flank-svg${flip ? " imp-hero-flank-svg--flip" : ""}`}
      viewBox="0 0 48 72"
      width={48}
      height={72}
      aria-hidden="true"
      focusable="false"
    >
      <g transform="translate(24 13) scale(0.19) translate(-50 -50)">
        <path fill="currentColor" d={WHISPER_STAR_PATH} opacity={0.92} />
      </g>
      <path
        fill="none"
        stroke="currentColor"
        strokeWidth="1.35"
        strokeLinecap="round"
        d="M24 30v8M14 36c2 10 6 18 10 26M34 36c-2 10-6 18-10 26M18 48q6-3 12 0M20 58q8 5 8 14"
      />
      <circle cx="24" cy="68" r="2.2" fill="currentColor" opacity={0.75} />
    </svg>
  );
}

export function ImpCornerFlourish({ flip = false }: { flip?: boolean }) {
  return (
    <svg
      className={`imp-flourish-svg${flip ? " imp-flourish-svg--flip" : ""}`}
      viewBox="0 0 36 52"
      width={36}
      height={52}
      aria-hidden="true"
      focusable="false"
    >
      <path
        fill="none"
        stroke="currentColor"
        strokeWidth="1.35"
        strokeLinecap="round"
        d="M18 4c-8 10-10 18-6 28M18 6c6 8 10 16 8 26M10 20q8-4 16 0M14 34q10 6 8 14"
      />
      <circle cx="18" cy="10" r="2.25" fill="currentColor" opacity={0.85} />
    </svg>
  );
}
