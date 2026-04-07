/** Small corner flourishes in the spirit of vintage playing-card engravings (crimson ink). */

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
