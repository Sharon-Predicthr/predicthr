DECLARE @sql NVARCHAR(MAX) = N'
  INSERT INTO dbo.interventions(short_text, long_description) VALUES
  (N''1:1 Manager Check-in'', N''Schedule a confidential 30–45 minute conversation to explore concerns, workload, recognition, and career goals. Agree on 2–3 concrete next steps.'' ),
  (N''Career Path Discussion'', N''Present growth options (skills, certifications, rotations). Co-create a 90-day development plan with milestones and sponsorship.'' ),
  (N''Pulse Survey / Stay Interview'', N''Run a short pulse or stay interview to capture drivers of engagement and flight risk.'' ),
  (N''Recognition Boost'', N''Provide specific, timely recognition for recent contributions (public shout-outs, spotlight, points).'' ),
  (N''Compensation Review'', N''Evaluate market parity, comprehensive rewards, and retention levers (bonus, equity refresh, promotion review).'' ),
  (N''Flexible Work Arrangement'', N''Offer remote/hybrid options, flexible hours, or schedule predictability to improve work-life fit.'' ),
  (N''Role/Project Realignment'', N''Align skills to work; re-scope deliverables or rotate projects to reduce friction.'' ),
  (N''Workload Rebalancing'', N''Reassign tasks, shift deadlines, or add temporary help to remove unsustainable peaks.'' ),
  (N''Wellbeing Resources'', N''Offer EAP, mental health days, or wellness resources; coach on boundaries.'' ),
  (N''Coaching & Mentoring'', N''Pair with mentor/coach for growth, feedback, and support.'' ),
  (N''Skills Training'', N''Provide targeted upskilling to match role demands and growth path.'' ),
  (N''Team Capacity Review'', N''Review headcount, bottlenecks, and demand; propose reprioritization or hiring plan.'' ),
  (N''Policy Refresher'', N''Reinforce attendance/ethics policies; clarify expectations and consequences.'' ),
  (N''Compliance Review'', N''Run a discreet compliance review with HR and Security for repeated anomalies.'' ),
  (N''Pattern Escalation'', N''Elevate repeated patterns to HR for documented follow-up.'' ),
  (N''Badge/Access Audit'', N''Audit badge usage, door mismatches, and geo anomalies.'' ),
  (N''Performance Check-in'', N''Clarify goals, expectations, and address blockers; set short review cadence.'' ),
  (N''HRBP Partnership'', N''Engage HR Business Partner to coordinate multi-pronged interventions.'' ),
  (N''Peer Buddy Program'', N''Assign peer support for integration and engagement.'' ),
  (N''Escalation to HRBP'', N''Escalate risk pattern to HRBP for coordinated retention/compliance actions.'' ),
  /* >>> NEW: exact 0-score filler shown by reports */
  (N''No Intervention Needed'', N''Score is low; informational only — monitor within normal cadence.'');
';
EXEC sys.sp_executesql @sql;
