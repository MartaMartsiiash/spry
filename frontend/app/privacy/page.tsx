import type { Metadata } from "next"
import Link from "next/link"

export const metadata: Metadata = {
  title: "Privacy policy — SuccessfulSuccess",
  description: "What SuccessfulSuccess stores when you sign in.",
}

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-6 py-16">
      <h1 className="text-2xl font-semibold tracking-tight">Privacy policy</h1>
      <p className="text-muted-foreground mt-2 text-sm">SuccessfulSuccess, a course project.</p>

      <div className="mt-8 space-y-4 text-sm leading-6">
        <p>
          SuccessfulSuccess stores the meetings you create and the profile that comes with
          your sign-in: email address, name, and the identifier of the account that signed
          in. Sign-in is provided by Amazon Cognito. If you choose Continue with Google,
          Google tells Cognito your email, name, and whether that email is verified. The
          site never receives your Google password.
        </p>
        <p>
          This information is used only to show you your own meetings and your email in
          the header. It is not sold and it is not used for advertising.
        </p>
        <p>
          You can stop using the site at any time with Sign out. Removing the account
          deletes the Cognito user and, with it, the meetings stored for that account.
        </p>
      </div>

      <p className="mt-10 text-sm">
        <Link href="/login/" className="underline underline-offset-4">
          Sign in
        </Link>
      </p>
    </main>
  )
}
