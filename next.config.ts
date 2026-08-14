import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Self-hosting on Hostinger's Node.js app manager (Passenger) — a
  // standalone server.js that only needs node_modules for a handful of
  // native deps copied in, not the full node_modules tree.
  output: "standalone",
  experimental: {
    serverActions: {
      // Default is 1MB — too small for scanned invoices/quotations attached
      // to requisitions.
      bodySizeLimit: "15mb",
    },
  },
};

export default nextConfig;
