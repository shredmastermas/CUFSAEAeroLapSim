/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,jsx}",
    "../handover/dashboard/*.jsx",
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ["Roboto", "system-ui", "sans-serif"],
        mono: ['"Roboto Mono"', "ui-monospace", "monospace"],
        display: ['"Roboto Condensed"', "Roboto", "sans-serif"],
      },
    },
  },
  plugins: [],
};
