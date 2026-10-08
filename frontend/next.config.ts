import type { NextConfig } from "next";

const isExport = process.env.NEXT_OUTPUT === "export";

const nextConfig: NextConfig = {
  // "standalone" is what the `production` stage in the Dockerfile needs.
  // `make aws-deploy-frontend` sets NEXT_OUTPUT=export instead, to get the
  // static files that go to S3 behind CloudFront.
  output: isExport ? "export" : "standalone",
  // Cognito callback URLs must match exactly, including the trailing slash
  // (/login/, /auth/callback/). The export and local dev use the same paths.
  trailingSlash: true,
};

export default nextConfig;
