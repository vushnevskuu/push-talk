/**
 * Мелкий звёздный паттерн в духе гравюр на игральных картах.
 * Цвета — из палитры .page-whispering-imps (crimson / ink), без тяжёлых библиотек.
 */

const STAR = "M12 2l2.6 7.9h8.4l-6.8 4.9 2.6 7.9-6.8-4.9-6.8 4.9 2.6-7.9-6.8-4.9h8.4z";

const DIAMOND = "M0-2.2L2.4 0 0 2.2-2.4 0Z";

export function WhisperStarfield() {
  return (
    <div className="whisper-starfield" aria-hidden>
      <svg
        className="whisper-starfield-svg"
        xmlns="http://www.w3.org/2000/svg"
        preserveAspectRatio="none"
        width="100%"
        height="100%"
      >
        <defs>
          <pattern
            id="whisper-card-stars"
            width="52"
            height="52"
            patternUnits="userSpaceOnUse"
          >
            <g className="whisper-starfield-shapes">
              <path
                fill="#a61c1c"
                fillOpacity={0.11}
                transform="translate(7,9) scale(0.2)"
                d={STAR}
              />
              <path
                fill="#6f1414"
                fillOpacity={0.14}
                transform="translate(30,6) scale(0.14)"
                d={STAR}
              />
              <path
                fill="#a61c1c"
                fillOpacity={0.09}
                transform="translate(40,34) scale(0.17)"
                d={STAR}
              />
              <path
                fill="#6f1414"
                fillOpacity={0.12}
                transform="translate(10,36) scale(0.12)"
                d={STAR}
              />
              <path
                fill="#a61c1c"
                fillOpacity={0.1}
                transform="translate(24,22) scale(0.16)"
                d={STAR}
              />
              <path
                fill="#14120f"
                fillOpacity={0.06}
                transform="translate(44,14)"
                d={DIAMOND}
              />
              <path
                fill="#14120f"
                fillOpacity={0.05}
                transform="translate(3,24) scale(0.85)"
                d={DIAMOND}
              />
              <path
                fill="#a61c1c"
                fillOpacity={0.08}
                transform="translate(18,44) scale(0.11)"
                d={STAR}
              />
            </g>
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#whisper-card-stars)" />
      </svg>
    </div>
  );
}
