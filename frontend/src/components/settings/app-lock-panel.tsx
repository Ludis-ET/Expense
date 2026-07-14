"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Fingerprint, Lock, LockOpen, ShieldCheck, Timer } from "lucide-react";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Field, Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { useAppLock } from "@/lib/app-lock-context";
import type { AutoLockMinutes } from "@/lib/app-lock-crypto";
import { cn } from "@/lib/utils";

const AUTO_LOCK_OPTIONS: { value: AutoLockMinutes; label: string }[] = [
  { value: 0, label: "Only when I leave the app" },
  { value: 1, label: "After 1 minute idle" },
  { value: 2, label: "After 2 minutes idle" },
  { value: 5, label: "After 5 minutes idle" },
  { value: 15, label: "After 15 minutes idle" },
];

export function AppLockPanel() {
  const lock = useAppLock();
  const [setupOpen, setSetupOpen] = useState(false);
  const [changeOpen, setChangeOpen] = useState(false);
  const [disableOpen, setDisableOpen] = useState(false);

  if (!lock.ready) return null;

  return (
    <Card>
      <CardHeader>
        <div>
          <CardTitle className="flex items-center gap-2">
            <ShieldCheck className="h-5 w-5 text-primary" />
            App lock
          </CardTitle>
          <CardDescription>
            PIN and biometrics (Face ID, Touch ID, Windows Hello, fingerprint)
            keep Santim private on this device. Secrets never leave your
            browser.
          </CardDescription>
        </div>
      </CardHeader>
      <CardContent className="space-y-5">
        {!lock.enabled ? (
          <div className="rounded-xl border border-dashed border-border bg-surface-muted/40 p-5 text-center">
            <Lock className="mx-auto h-8 w-8 text-muted" />
            <p className="mt-3 text-sm font-medium">App lock is off</p>
            <p className="mt-1 text-xs text-muted">
              Anyone with your open session can see balances until you enable a
              PIN.
            </p>
            <Button
              className="mt-4"
              size="sm"
              onClick={() => setSetupOpen(true)}
            >
              Set up PIN lock
            </Button>
          </div>
        ) : (
          <>
            <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl bg-emerald-500/8 px-4 py-3">
              <div className="flex items-center gap-2 text-sm font-medium text-emerald-700 dark:text-emerald-400">
                <Lock className="h-4 w-4" />
                Lock is active
              </div>
              <Button size="sm" variant="outline" onClick={() => lock.lock()}>
                Lock now
              </Button>
            </div>

            <div className="space-y-3">
              <Field label="Auto-lock">
                <Select
                  value={String(lock.autoLockMinutes)}
                  onChange={(e) =>
                    lock.setAutoLockMinutes(
                      Number(e.target.value) as AutoLockMinutes,
                    )
                  }
                >
                  {AUTO_LOCK_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </Select>
              </Field>

              <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-border px-4 py-3">
                <input
                  type="checkbox"
                  className="mt-1"
                  checked={lock.lockOnBlur}
                  onChange={(e) => lock.setLockOnBlur(e.target.checked)}
                />
                <span>
                  <span className="flex items-center gap-1.5 text-sm font-medium">
                    <Timer className="h-3.5 w-3.5 text-muted" />
                    Lock when switching apps
                  </span>
                  <span className="mt-0.5 block text-xs text-muted">
                    Re-locks after you hide the tab or leave the PWA for a short
                    while.
                  </span>
                </span>
              </label>
            </div>

            <div className="rounded-xl border border-border p-4">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="flex items-center gap-2 text-sm font-medium">
                    <Fingerprint className="h-4 w-4 text-primary" />
                    Biometrics
                  </p>
                  <p className="mt-1 text-xs text-muted">
                    {lock.hasBiometric
                      ? "Face ID / fingerprint / Windows Hello is enrolled on this device."
                      : lock.biometricAvailable
                        ? "Use Face ID, Touch ID, Windows Hello, or device fingerprint for faster unlock."
                        : "Platform biometrics are not available in this browser. PIN still works."}
                  </p>
                </div>
                {lock.hasBiometric ? (
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => lock.removeBiometrics()}
                  >
                    Remove
                  </Button>
                ) : (
                  <Button
                    size="sm"
                    disabled={!lock.biometricAvailable}
                    onClick={async () => {
                      const res = await lock.enrollBiometrics();
                      if (res.ok) toast.success("Biometrics enrolled");
                      else toast.error(res.error ?? "Failed");
                    }}
                  >
                    Enroll
                  </Button>
                )}
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              <Button
                size="sm"
                variant="outline"
                onClick={() => setChangeOpen(true)}
              >
                Change PIN
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setDisableOpen(true)}
              >
                <LockOpen className="h-3.5 w-3.5" />
                Turn off lock
              </Button>
            </div>
          </>
        )}
      </CardContent>

      <SetupPinModal open={setupOpen} onClose={() => setSetupOpen(false)} />
      <ChangePinModal open={changeOpen} onClose={() => setChangeOpen(false)} />
      <DisableLockModal
        open={disableOpen}
        onClose={() => setDisableOpen(false)}
      />
    </Card>
  );
}

function SetupPinModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const { enableLock, enrollBiometrics, biometricAvailable } = useAppLock();
  const [pin, setPin] = useState("");
  const [confirm, setConfirm] = useState("");
  const [enrollBio, setEnrollBio] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) {
      setPin("");
      setConfirm("");
      setEnrollBio(true);
    }
  }, [open]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (pin !== confirm) {
      toast.error("PINs do not match");
      return;
    }
    setSaving(true);
    const res = await enableLock(pin);
    if (!res.ok) {
      toast.error(res.error ?? "Could not enable lock");
      setSaving(false);
      return;
    }
    if (enrollBio && biometricAvailable) {
      const bio = await enrollBiometrics();
      if (bio.ok) toast.success("App lock + biometrics ready");
      else toast.success("App lock enabled   biometrics skipped");
    } else {
      toast.success("App lock enabled");
    }
    setSaving(false);
    onClose();
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Set up app lock"
      description="Choose a 4–8 digit PIN for this device."
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label="PIN">
          <Input
            type="password"
            inputMode="numeric"
            autoComplete="new-password"
            pattern="\d{4,8}"
            maxLength={8}
            required
            value={pin}
            onChange={(e) =>
              setPin(e.target.value.replace(/\D/g, "").slice(0, 8))
            }
            placeholder="••••"
          />
        </Field>
        <Field label="Confirm PIN">
          <Input
            type="password"
            inputMode="numeric"
            autoComplete="new-password"
            pattern="\d{4,8}"
            maxLength={8}
            required
            value={confirm}
            onChange={(e) =>
              setConfirm(e.target.value.replace(/\D/g, "").slice(0, 8))
            }
            placeholder="••••"
          />
        </Field>
        {biometricAvailable && (
          <label className={cn("flex items-start gap-2 text-sm")}>
            <input
              type="checkbox"
              className="mt-1"
              checked={enrollBio}
              onChange={(e) => setEnrollBio(e.target.checked)}
            />
            <span>
              <span className="font-medium">Also enroll biometrics</span>
              <span className="block text-xs text-muted">
                Face ID, Touch ID, Windows Hello, or fingerprint.
              </span>
            </span>
          </label>
        )}
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            Enable lock
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function ChangePinModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const { changePin } = useAppLock();
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [confirm, setConfirm] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) {
      setCurrent("");
      setNext("");
      setConfirm("");
    }
  }, [open]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (next !== confirm) {
      toast.error("New PINs do not match");
      return;
    }
    setSaving(true);
    const res = await changePin(current, next);
    setSaving(false);
    if (!res.ok) {
      toast.error(res.error ?? "Failed");
      return;
    }
    toast.success("PIN updated");
    onClose();
  }

  return (
    <Modal open={open} onClose={onClose} title="Change PIN">
      <form onSubmit={submit} className="space-y-4">
        <Field label="Current PIN">
          <Input
            type="password"
            inputMode="numeric"
            maxLength={8}
            required
            value={current}
            onChange={(e) =>
              setCurrent(e.target.value.replace(/\D/g, "").slice(0, 8))
            }
          />
        </Field>
        <Field label="New PIN">
          <Input
            type="password"
            inputMode="numeric"
            maxLength={8}
            required
            value={next}
            onChange={(e) =>
              setNext(e.target.value.replace(/\D/g, "").slice(0, 8))
            }
          />
        </Field>
        <Field label="Confirm new PIN">
          <Input
            type="password"
            inputMode="numeric"
            maxLength={8}
            required
            value={confirm}
            onChange={(e) =>
              setConfirm(e.target.value.replace(/\D/g, "").slice(0, 8))
            }
          />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving}>
            Save PIN
          </Button>
        </div>
      </form>
    </Modal>
  );
}

function DisableLockModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const { disableLock } = useAppLock();
  const [pin, setPin] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) setPin("");
  }, [open]);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const res = await disableLock(pin);
    setSaving(false);
    if (!res.ok) {
      toast.error(res.error ?? "Failed");
      return;
    }
    toast.success("App lock turned off");
    onClose();
  }

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Turn off app lock"
      description="Enter your PIN to confirm. Biometrics on this device will be cleared."
    >
      <form onSubmit={submit} className="space-y-4">
        <Field label="PIN">
          <Input
            type="password"
            inputMode="numeric"
            maxLength={8}
            required
            autoFocus
            value={pin}
            onChange={(e) =>
              setPin(e.target.value.replace(/\D/g, "").slice(0, 8))
            }
          />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button type="submit" loading={saving} variant="danger">
            Turn off
          </Button>
        </div>
      </form>
    </Modal>
  );
}
