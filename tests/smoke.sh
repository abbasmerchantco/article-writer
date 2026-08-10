#!/usr/bin/env bash
# smoke.sh — the only test harness that matters now: init-run.sh + publish.sh against
# the simplified, single-folder article-writer (docs/requirements.md §3-4).
# Runs entirely in a throwaway workdir so the repo is never polluted.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INIT="$REPO/scripts/init-run.sh"
PUB="$REPO/scripts/publish.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

PASS=0; FAIL=0
ok()   { echo "  ok   - $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL - $1"; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1 :: [$2]"; fi; }
jget() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2], ''))" "$1" "$2" 2>/dev/null; }

echo "== init-run.sh =="

out1="$(AW_AUDIENCE="film nerds" AW_INTENTION="convince them to watch it" \
        AW_POST_CATEGORY="movies" "$INIT" "A review of a great heist movie" 2>/dev/null)"
rc=$?
run1="${out1#RUN }"
check "prints RUN and exits 0" "[ $rc -eq 0 ] && [ -n '$run1' ]"
check "run folder exists directly under cwd" "[ -d '$run1' ]"
check "no input/interim/output subfolders (flat layout)" "[ ! -d input ] && [ ! -d interim ] && [ ! -d output ]"
check "internal .article-writer/ subfolder exists" "[ -d '$run1/.article-writer' ]"
BRIEF="$run1/.article-writer/brief.json"
check "brief.json is valid JSON" "python3 -c \"import json;json.load(open('$BRIEF'))\""
check "brief.json has raw_topic verbatim" "[ \"\$(jget '$BRIEF' raw_topic)\" = 'A review of a great heist movie' ]"
check "brief.json carries audience" "[ \"\$(jget '$BRIEF' audience)\" = 'film nerds' ]"
check "brief.json carries post_category" "[ \"\$(jget '$BRIEF' post_category)\" = 'movies' ]"
check "brief.json status starts as drafting" "[ \"\$(jget '$BRIEF' status)\" = 'drafting' ]"

echo "== init-run.sh: dedup =="
before="$(ls -d */ 2>/dev/null | wc -l | tr -d ' ')"
dup_out="$("$INIT" "a review OF A great Heist Movie!!" 2>/dev/null)"; dup_rc=$?
after="$(ls -d */ 2>/dev/null | wc -l | tr -d ' ')"
check "slug collision exits 2" "[ $dup_rc -eq 2 ]"
check "slug collision prints DUPLICATE_MATCH" "printf '%s' '$dup_out' | grep -q '^DUPLICATE_MATCH '"
check "slug collision creates nothing" "[ '$before' = '$after' ]"

out2="$("$INIT" --force-new "a review OF A great Heist Movie!!" 2>/dev/null)"
run2="${out2#RUN }"
check "--force-new bypasses dedup" "[ -n '$run2' ] && [ '$run2' != '$run1' ]"

echo "== publish.sh =="

# 300 words total (298 filler + "Intro"/"line.") -> ceil(300/225) = 2 minutes, so this
# exercises a readTime > 1 deterministically.
python3 - "$run1/.article-writer/draft.md" <<'PY'
import sys
words = (["word"] * 298)
open(sys.argv[1], "w", encoding="utf-8").write("Intro line.\n\n" + " ".join(words) + "\n")
PY

"$PUB" "$run1" "$WORK" >/dev/null 2>&1
pub_rc=$?
check "publish.sh exits 0 with no frontmatter.json (defaults kick in)" "[ $pub_rc -eq 0 ]"
ART="$run1/article.md"
check "article.md written at run-folder top level" "[ -f '$ART' ]"
check "article.md starts with frontmatter delimiter" "head -1 '$ART' | grep -q '^---$'"
check "article.md has a title line (defaulted to raw_topic)" "grep -q '^title:' '$ART'"
check "article.md category comes from post_category" "grep -q '^category: movies$' '$ART'"
check "article.md has a quoted readTime" "grep -qE '^readTime: \"[0-9]+\"$' '$ART'"
check "readTime is 2 for a 300-word draft at 225wpm" "grep -q '^readTime: \"2\"$' '$ART'"
check "article.md defaults published to false" "grep -q '^published: false$' '$ART'"
check "article.md defaults featured to false" "grep -q '^featured: false$' '$ART'"
check "article.md defaults coverImage to a TODO placeholder" "grep -q 'coverImage: /images/uploads/TODO-' '$ART'"
check "article.md carries layout constant" "grep -q '^layout: layouts/post.njk$' '$ART'"
check "article.md body includes the draft content" "grep -q 'Intro line.' '$ART'"

SCOPE="$run1/scope.md"
check "scope.md written at run-folder top level" "[ -f '$SCOPE' ]"
check "scope.md records the topic" "grep -q 'A review of a great heist movie' '$SCOPE'"
check "scope.md records the audience" "grep -q 'film nerds' '$SCOPE'"
check "brief.json flipped to published" "[ \"\$(jget '$BRIEF' status)\" = 'published' ]"

echo "== publish.sh: model-supplied frontmatter overrides defaults =="
out3="$(AW_POST_CATEGORY=travel "$INIT" --force-new "A trip that went sideways" 2>/dev/null)"
run3="${out3#RUN }"
printf 'A short trip account.\n' > "$run3/.article-writer/draft.md"
python3 -c "
import json
json.dump({'title': 'Custom Title', 'excerpt': 'A short excerpt.', 'featured': True,
           'published': True, 'coverImage': '/images/uploads/real.jpg',
           'image': '/images/uploads/real.svg', 'imageAlt': 'A real alt text'},
          open('$run3/.article-writer/frontmatter.json', 'w'))
"
"$PUB" "$run3" "$WORK" >/dev/null 2>&1
ART3="$run3/article.md"
check "custom title used verbatim" "grep -q '^title: Custom Title$' '$ART3'"
check "custom featured:true honored" "grep -q '^featured: true$' '$ART3'"
check "custom published:true honored" "grep -q '^published: true$' '$ART3'"
check "custom coverImage honored (no placeholder)" "grep -q '^coverImage: /images/uploads/real.jpg$' '$ART3'"

echo
echo "==== $PASS passed, $FAIL failed ===="
[ "$FAIL" -eq 0 ]
