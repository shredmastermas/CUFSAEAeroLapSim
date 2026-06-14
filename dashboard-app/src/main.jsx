import React from "react";
import { createRoot } from "react-dom/client";

// Bundled locally — no font/CSS CDNs, works on isolated networks.
import "@fontsource/roboto/400.css";
import "@fontsource/roboto/500.css";
import "@fontsource/roboto/700.css";
import "@fontsource/roboto-mono/400.css";
import "@fontsource/roboto-mono/500.css";
import "@fontsource/roboto-mono/700.css";
import "@fontsource/roboto-condensed/700.css";
import "./index.css";

// Single source of truth: the committed consumer the data contract targets.
import App from "../../handover/dashboard/t27-aero-dashboard.jsx";

createRoot(document.getElementById("root")).render(<App />);
