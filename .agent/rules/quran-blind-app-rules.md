---
trigger: always_on
---


# RULES.md — Refinement Governance Rules

## Scope Lock

This refinement branch is restricted to improving already approved systems only.

Allowed domains:

• Audio playback engine  
• Ayah navigation  
• Repeat & memorization loops  
• Voice command routing  
• Offline download systems  
• Translation synchronization  
• Accessibility flows  
• Phonetic matching  
• Integrity validation  

No new feature ideation is permitted in this branch.

---

## Accessibility Supremacy

All refinements must preserve blind‑first usability.

Requirements:

• No visual‑only interactions  
• Audio feedback for every state change  
• Full screen reader traversal  
• Voice command parity for all actions  

Accessibility regressions block merges.

---

## Quran Integrity Protection

Sacred text handling is immutable.

Rules:

• Tanzil verified text only  
• No Arabic text mutation  
• Translation edits prohibited  
• Checksum validation enforced  
• Source domains whitelisted  

Any violation halts build pipelines.

---

## Performance Budgets

Refinements must remain within latency ceilings:

• Audio seek < 10 ms  
• Repeat transition gapless  
• Voice execution < 1 s  
• DB queries < 50 ms  

Exceeding thresholds requires native optimization.

---

## Native Boundary Enforcement

C++ required for:

• Audio decoding  
• Repeat loops  
• Phonetic matching  
• Integrity validation  

Dart restricted to orchestration, UI, and services.

---

## Offline First Preservation

No refinement may introduce internet dependency.

Must maintain:

• Offline playback  
• Cached metadata  
• Local translations  
• Download resilience  

---

## Regression Safeguards

All refinements must include:

• Unit tests  
• Performance benchmarks  
• Accessibility audits  
• Failure scenario validation  

---

## Merge Approval Criteria

Refinements merge only if:

• No accessibility regression  
• No latency increase  
• No schema conflicts  
• Integrity validation intact  