# Builds one flat entry (the snapshot contract reopen.sh reads) from the raw herdr replies
# remember.sh saved. Run it through build_entry.sh <dir>, which holds the jq command.
# Every field is present; absent data is null. `v` is the contract version.

def first_or_null: if length > 0 then .[0] else null end;
def inside($a; $b): $a.x >= $b.x and $a.y >= $b.y
  and $a.x + $a.width <= $b.x + $b.width and $a.y + $a.height <= $b.y + $b.height;
def touches($a; $b; $d): if $d == "right"
  then ($a.x + $a.width == $b.x) or ($b.x + $b.width == $a.x)
  else ($a.y + $a.height == $b.y) or ($b.y + $b.height == $a.y) end;

($pane | first_or_null | .result.pane) as $p
| ($layout | first_or_null | .result.layout) as $l
| ($procs | first_or_null | .result.process_info) as $pi
| ($tab | first_or_null | .result.tab) as $t
| ($ws | first_or_null | .result.workspace) as $w
| ($agent | first_or_null) as $a
| ($p.foreground_cwd // $p.cwd) as $cwd
# The sibling: the other pane of the smallest split that held this pane, preferring one that
# touched it along the split axis. side "after" = this pane was right of / below the sibling.
| (if $l == null then null else
    ($l.panes[] | select(.pane_id == $p.pane_id) | .rect) as $r
    | ([$l.splits[]? | select(inside($r; .rect))] | sort_by(.rect.width * .rect.height) | first) as $s
    | if $s == null then null else
        ([$l.panes[] | select(.pane_id != $p.pane_id and inside(.rect; $s.rect))]
          | sort_by([(if touches(.rect; $r; $s.direction) then 0 else 1 end), -(.rect.width * .rect.height)])
          | first) as $o
        | if $o == null then null else
            { pane_id: $o.pane_id, direction: $s.direction,
              side: (if ($s.direction == "right" and $r.x > $o.rect.x) or ($s.direction == "down" and $r.y > $o.rect.y)
                     then "after" else "before" end) }
          end
      end
  end) as $sib
# Processes: the name (argv0 basename, login dash stripped; the same rule close.sh uses) of
# everything in the foreground, and the argv of the command the shell launched (the process
# group leader) when it is not the shell itself.
| ([$pi.foreground_processes[]? | select(.argv | type == "array" and length > 0)]) as $fg
| def pname: (.argv0 // .argv[0] | split("/") | last | ltrimstr("-"));
  ([$fg[] | pname]) as $names
| ([$fg[] | select(.pid == $pi.foreground_process_group_id and .pid != $pi.shell_pid)] | first) as $leader
| ([$fg[] | select(pname == "herdr-file-viewer")] | first) as $viewer
| {
    v: 1,
    pane_id: $p.pane_id, workspace_id: $p.workspace_id, tab_id: $p.tab_id,
    cwd: $cwd, label: ($p.label // null),
    # herdr labels a never-renamed tab with its number ("1"); the auto-title plugin writes
    # "N · name". Neither is a label the user set, so neither is restored.
    tab_label: ($t.label // null
      | if . != null and ((($t.number // null) != null and . == ($t.number | tostring)) or test("^[0-9]+ · "))
        then null else . end),
    workspace_label: ($w.label // null | if . == ($cwd // "" | split("/") | last) then null else . end),
    sibling: $sib,
    agent: ($a.agent // null), session: ($a.session // null),
    kind: (if $viewer != null then "viewer" elif ($a.session // null) != null then "agent" else "shell" end),
    programs: $names,
    argv: (if $leader != null and (($leader | pname) | test("^(zsh|bash|fish|sh|dash|login)$") | not) then $leader.argv else null end),
    viewer_open: (if $viewer == null then null else ($viewer.argv | index("--open") as $i | if $i then .[$i + 1] // null else null end) end)
  }
