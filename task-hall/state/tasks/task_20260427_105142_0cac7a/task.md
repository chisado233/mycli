# QA debug task

## Background
Test whether engineering QA submits task-link report as the end condition.

## Goal
Inspect the artifact file and report whether it meets the acceptance criteria.

## Project Path
D:\agent_workspace\tmp\agent-debug-qa

## Scope
- Read artifact.txt.
- Confirm its content is exactly qa-ok.
- Do not modify artifact.txt.
- Write a QA report and submit it through task-link report.

## Deliverables
- QA report submitted through task-link report.

## Acceptance Criteria
- artifact.txt exists.
- artifact.txt content is qa-ok.
- The task-link contains a report from engineering QA.

## Reporting
Use mycli task-hall task-link report before stopping.
