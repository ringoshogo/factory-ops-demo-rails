/**
 * 経路に埋める ID の検査。
 *
 * `/items/${id}` の形で組み立てる以上、`id` に `../customers/xxx` が入ると
 * **別リソースの操作になる**（fetch が正規化するため）。Server Action は
 * Proxy-Key を持つので、素通しにすると「鍵を持つ代理人」を利用者が
 * 自由に操作できることになる。
 *
 * 業務 API 側でも最前段で弾いているが（backend/internal/api/params.go）、
 * 組み立てる側でも止める。片方に寄せると、もう片方の変更で穴が開く。
 */
const UUID = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function isUUID(value: string): boolean {
  return UUID.test(value);
}
