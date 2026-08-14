export function AppHeader({ fullName }: { fullName: string }) {
  return (
    <header className="flex h-14 shrink-0 items-center gap-2 border-b bg-background px-4">
      <p className="text-sm font-medium">Welcome, {fullName}</p>
    </header>
  );
}
