import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Self-hosting on Hostinger's Node.js app manager (Passenger) — a
  // standalone server.js that only needs node_modules for a handful of
  // native deps copied in, not the full node_modules tree.
  output: "standalone",
  // Hostinger's build container kills the Turbopack CSS-transform
  // subprocess outright (TurbopackInternalError on app/globals.css: "node
  // process exited before we could connect to it with exit status: 0", no
  // output on either stream) — the signature of a process-level resource
  // limit, not a code/dependency issue (this build succeeds locally with
  // either bundler). Source maps add real memory pressure during the
  // build for no runtime benefit here, so drop them to leave more headroom
  // regardless of bundler.
  productionBrowserSourceMaps: false,
  experimental: {
    serverActions: {
      // Default is 1MB — too small for scanned invoices/quotations attached
      // to requisitions.
      bodySizeLimit: "15mb",
    },
  },
};

export default nextConfig;
