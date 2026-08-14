import Image from "next/image";
import { ChangePasswordForm } from "@/components/auth/change-password-form";

export default function ChangePasswordPage() {
  return (
    <div className="flex flex-1 items-center justify-center bg-muted/40 p-6">
      <div className="w-full max-w-sm rounded-xl border bg-card p-8 shadow-sm">
        <div className="flex flex-col items-center gap-3 text-center">
          <Image src="/actea-logo.png" alt="ACTEA" width={64} height={64} className="h-16 w-16" priority />
          <div>
            <h1 className="text-xl font-semibold">Set your password</h1>
            <p className="text-sm text-muted-foreground">
              You signed in with a temporary password. Choose a new one to continue.
            </p>
          </div>
        </div>
        <ChangePasswordForm />
      </div>
    </div>
  );
}
