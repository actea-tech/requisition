import Image from "next/image";

export default function LoginPage() {
  return (
    <div className="flex flex-1 items-center justify-center bg-muted/40 p-6">
      <div className="w-full max-w-sm rounded-xl border bg-card p-8 shadow-sm">
        <div className="flex flex-col items-center gap-3 text-center">
          <Image
            src="/actea-logo.png"
            alt="ACTEA"
            width={64}
            height={64}
            className="h-16 w-16"
            priority
          />
          <div>
            <h1 className="text-xl font-semibold">ACTEA Requisitions</h1>
            <p className="text-sm text-muted-foreground">
              Sign in with the account your administrator set up for you.
            </p>
          </div>
        </div>

        <div className="mt-8 space-y-4">
          <div className="space-y-1.5">
            <label htmlFor="email" className="text-sm font-medium">
              Email
            </label>
            <input
              id="email"
              type="email"
              placeholder="you@acteaweb.org"
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]"
            />
          </div>
          <div className="space-y-1.5">
            <label htmlFor="password" className="text-sm font-medium">
              Password
            </label>
            <input
              id="password"
              type="password"
              placeholder="••••••••"
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:ring-[3px]"
            />
          </div>
          <button
            type="button"
            className="inline-flex h-9 w-full items-center justify-center rounded-md bg-primary text-sm font-medium text-primary-foreground shadow-xs transition-colors hover:bg-primary/90"
          >
            Sign in
          </button>
        </div>
      </div>
    </div>
  );
}
