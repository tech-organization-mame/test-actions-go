# schemas/context.schema.json の jq 版（post.sh が使う）。スキーマを変えたら、ここと tests/lib/context_valid.jq を直す。
def isint: type == "number" and (. == floor);

. as $c
| ["schema_version","repository","route","state","run_id","run_attempt","head_sha","event",
   "pr_number","mention","same_sha_rerun","control_sha","evidence_sha256"] as $req
| ($req + ["fingerprint"]) as $allowed
| (type == "object")
  and ($req | all(. as $k | $c | has($k)))
  and ((($c | keys) - $allowed) | length == 0)
  and ($c.schema_version == 1)
  and ($c.repository | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))
  and ($c.route | IN("pr", "merge", "out_of_scope"))
  and ($c.state | IN("out_of_scope", "record_only", "post_target", "analysis_failed"))
  and ($c.run_id | (isint and . >= 1))
  and ($c.run_attempt | (isint and . >= 1))
  and ($c.head_sha | type == "string" and test("^[0-9a-f]{40}$"))
  and ($c.event | type == "string" and length >= 1 and length <= 40)
  and ($c.pr_number == null or ($c.pr_number | (isint and . >= 1)))
  and ($c.mention == null or ($c.mention | type == "string" and test("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$")))
  and ($c.same_sha_rerun | IN("none", "succeeded", "failed"))
  and ((($c | has("fingerprint")) | not) or $c.fingerprint == null
       or ($c.fingerprint | type == "string" and test("^[0-9a-f]{64}$")))
  and ($c.control_sha | type == "string" and test("^[0-9a-f]{40}$"))
  and ($c.evidence_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
  # allOf
  and ($c.route != "pr" or ($c.pr_number | type == "number"))
  and ($c.route != "out_of_scope" or ($c.state | IN("out_of_scope", "record_only")))
  and ($c.state != "post_target" or ($c.route | IN("pr", "merge")))
