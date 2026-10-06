export interface PayeeRow {
  /** Client-side identity only (stable React key); the server replaces the whole list on save. */
  key: string;
  payee_name: string;
  payee_contact: string;
  amount: string;
  payment_mode: string;
  payment_mode_details: string;
}

export type PayeeFieldKey = Exclude<keyof PayeeRow, "key">;

// Order the fields appear in within each payee block. Labels/help text/
// required flags still come from Settings > Form Fields (form_field_config).
export const PAYEE_FIELD_KEYS = [
  "payee_name",
  "payee_contact",
  "amount",
  "payment_mode",
  "payment_mode_details",
] as const satisfies readonly PayeeFieldKey[];

// Pass a fixed key for anything built during the initial render — a random
// one would differ between the server render and hydration.
export function emptyPayee(key: string = crypto.randomUUID()): PayeeRow {
  return {
    key,
    payee_name: "",
    payee_contact: "",
    amount: "",
    payment_mode: "",
    payment_mode_details: "",
  };
}

export function payeesTotal(payees: PayeeRow[]): number {
  const sum = payees.reduce((acc, p) => {
    const n = Number.parseFloat(p.amount);
    return Number.isFinite(n) ? acc + n : acc;
  }, 0);
  return Math.round(sum * 100) / 100;
}
