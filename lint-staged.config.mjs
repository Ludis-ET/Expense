import path from 'node:path';

/**
 * Run package-local ESLint on staged files (paths relative to that package).
 * @param {string} pkgDir
 * @param {string[]} filenames
 */
function eslintIn(pkgDir, filenames) {
  const files = filenames
    .map((f) => path.relative(pkgDir, f).replace(/\\/g, '/'))
    .filter((f) => f && !f.startsWith('..'))
    .map((f) => `"${f}"`)
    .join(' ');
  if (!files) return [];
  // --dir keeps cwd in the package so flat eslint configs resolve correctly
  return [`pnpm --dir ${pkgDir} exec eslint --max-warnings=0 -- ${files}`];
}

/** @type {import('lint-staged').Configuration} */
export default {
  'frontend/**/*.{js,jsx,mjs,ts,tsx}': (filenames) => eslintIn('frontend', filenames),
  'backend/**/*.{js,mjs,ts}': (filenames) => eslintIn('backend', filenames),
};
