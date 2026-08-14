import { requireProfile } from "@/lib/auth/session";
import { NameForm, PasswordForm } from "@/components/profile/profile-forms";

export default async function ProfilePage() {
  const profile = await requireProfile();

  return (
    <div className="max-w-lg space-y-4">
      <h1 className="text-2xl font-semibold">My Profile</h1>
      <NameForm fullName={profile.full_name} email={profile.email} />
      <PasswordForm />
    </div>
  );
}
