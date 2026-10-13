"use client";

import { useActionState, useRef } from "react";
import { ErrorNotice } from "@/components/error-notice";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { login } from "@/lib/auth-actions";
import { DEMO_ACCOUNTS, DEMO_PASSWORD, TENANT_LABELS } from "@/lib/demo-accounts";
import { IDLE } from "@/lib/form-state";

/**
 * メールアドレスとパスワードの入力欄と、シードのアカウントの一覧。一覧の行を押すと、そのアカウントの資格情報が
 * 入力欄に入る。テナントを切り替えるには、ログアウトして別のテナントのアカウントでログインする。
 */
export function LoginForm() {
  const [state, action, pending] = useActionState(login, IDLE);
  const email = useRef<HTMLInputElement>(null);
  const password = useRef<HTMLInputElement>(null);
  const tenants = [...new Set(DEMO_ACCOUNTS.map((a) => a.tenant))];

  function fill(address: string) {
    if (email.current) email.current.value = address;
    if (password.current) password.current.value = DEMO_PASSWORD;
  }

  return (
    <div className="space-y-6">
      <form action={action} className="space-y-3">
        {state.status === "error" && <ErrorNotice data-testid="form-error">{state.message}</ErrorNotice>}
        <div className="space-y-1.5">
          <Label htmlFor="email">メールアドレス</Label>
          <Input id="email" name="email" type="email" autoComplete="username" required ref={email} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="password">パスワード</Label>
          <Input id="password" name="password" type="password" autoComplete="current-password" required ref={password} />
        </div>
        <Button type="submit" className="w-full" disabled={pending}>
          ログイン
        </Button>
      </form>

      <div className="space-y-3">
        <h2 className="text-sm font-semibold">デモのアカウント</h2>
        <p className="text-muted-foreground text-[13px]">
          押すと入力欄に入ります。パスワードはどれも <code className="font-medium">{DEMO_PASSWORD}</code> です。
        </p>
        {tenants.map((tenant) => (
          <div key={tenant} className="space-y-1">
            <p className="text-muted-foreground text-xs font-medium">{TENANT_LABELS[tenant] ?? tenant}</p>
            <ul className="space-y-1">
              {DEMO_ACCOUNTS.filter((a) => a.tenant === tenant).map((account) => (
                <li key={account.email}>
                  <button
                    type="button"
                    data-testid="demo-account"
                    onClick={() => fill(account.email)}
                    className="rounded-control hover:bg-muted flex w-full items-baseline justify-between gap-3 px-2 py-1.5 text-left text-sm"
                  >
                    <span className="min-w-0 truncate">{account.email}</span>
                    <span className="text-muted-foreground shrink-0 text-xs">
                      {account.name}・{account.role === "admin" ? "管理者" : "担当者"}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </div>
  );
}
