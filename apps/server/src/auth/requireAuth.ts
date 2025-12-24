import type { Request, Response, NextFunction } from "express";
import { getSession } from "./sessions.js";

export type AuthedRequest = Request & { accountId: string };

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const sessionId =
    req.header("x-session-id") ||
    req.header("authorization")?.replace("Bearer ", "");

  if (!sessionId) return res.status(401).json({ error: "Missing session" });

  const session = getSession(sessionId);
  if (!session) return res.status(401).json({ error: "Invalid session" });

  (req as AuthedRequest).accountId = session.accountId;
  next();
}
