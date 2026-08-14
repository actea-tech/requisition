"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

// Deliberately does NOT call redirect() on success — doing so from inside
// a useActionState action occasionally let the raw RSC response flash as
// text if the click landed before hydration finished. The client now
// navigates itself via router.push once it sees a successful, no-error
// state (see login-form.tsx).
export async function signIn(
  _prevState: { error: string | null },
  formData: FormData,
): Promise<{ error: string | null }> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");

  if (!email || !password) {
    return { error: "Enter your email and password." };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    return { error: "Incorrect email or password." };
  }

  return { error: null };
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}
