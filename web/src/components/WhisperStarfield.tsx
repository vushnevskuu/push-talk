/**
 * Звёздный фон из геометрии `public/whisper-star.svg` (папка «мусор» на рабочем столе).
 */

import { WHISPER_STAR_PATH } from "@/lib/whisperStarPath";

function StarAt(
  x: number,
  y: number,
  scale: number,
  fill: string,
  opacity: number,
) {
  return (
    <path
      transform={`translate(${x},${y}) scale(${scale})`}
      d={WHISPER_STAR_PATH}
      fill={fill}
      fillOpacity={opacity}
    />
  );
}

function StarCluster({ offsetX = 0, offsetY = 0 }: { offsetX?: number; offsetY?: number }) {
  const t = `translate(${offsetX},${offsetY})`;
  return (
    <g transform={t}>
      {StarAt(4, 5, 0.095, "#a03855", 0.16)}
      {StarAt(22, 3, 0.078, "#c4546e", 0.14)}
      {StarAt(32, 22, 0.085, "#8e2f4a", 0.12)}
      {StarAt(8, 26, 0.065, "#6b2540", 0.14)}
      {StarAt(18, 16, 0.088, "#b83d5c", 0.13)}
      {StarAt(36, 12, 0.055, "#5c2033", 0.08)}
      {StarAt(2, 18, 0.05, "#5c2033", 0.07)}
      {StarAt(14, 34, 0.058, "#a03855", 0.11)}
      {StarAt(28, 36, 0.062, "#de516c", 0.1)}
    </g>
  );
}

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
          <pattern id="whisper-card-stars-a" width="44" height="44" patternUnits="userSpaceOnUse">
            <StarCluster />
          </pattern>
          <pattern id="whisper-card-stars-b" width="44" height="44" patternUnits="userSpaceOnUse">
            <StarCluster offsetX={22} offsetY={22} />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill="url(#whisper-card-stars-a)" opacity={0.55} />
        <rect width="100%" height="100%" fill="url(#whisper-card-stars-b)" opacity={0.38} />
      </svg>
    </div>
  );
}
