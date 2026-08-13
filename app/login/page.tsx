import Image from "next/image";
import { LoginForm } from "@/components/auth/login-form";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;

  return (
    <div className="flex flex-1 items-center justify-center bg-muted/40 p-6">
      <div className="w-full max-w-sm rounded-xl border bg-card p-8 shadow-sm">
        <div className="flex flex-col items-center gap-3 text-center">
          <Image src="/actea-logo.png" alt="ACTEA" width={64} height={64} className="h-16 w-16" priority />
          <div>
            <h1 className="text-xl font-semibold">ACTEA Requisitions</h1>
            <p className="text-sm text-muted-foreground">
              Sign in with the account your administrator set up for you.
            </p>
          </div>
        </div>

        <LoginForm next={next ?? "/"} />
      </div>
    </div>
  );
}
