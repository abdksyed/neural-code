#!/usr/bin/env bash
#
# Walk the NeuralCode history one stage at a time.
#
#   bash present.sh list       every stage, numbered
#   bash present.sh 7          jump to stage 7
#   bash present.sh next       next stage
#   bash present.sh prev       previous stage
#   bash present.sh diff       the patch this stage introduced
#   bash present.sh files      what this stage touched
#   bash present.sh show <f>   print a file as it was at this stage
#   bash present.sh run        run the agent as of this stage
#   bash present.sh setup      copy .agents/.env to ~/.agents/env
#   bash present.sh main       back to the tip
#
# Switching refuses to clobber uncommitted edits. Add --force to discard them.

set -euo pipefail

cd "$(dirname "$0")"

# Load the local dotenv file for every command in this script. This exports
# credentials to child processes such as uv, llm.py, and neuralcode.
DOTENV=
for candidate in .agents/.env .agents/env; do
	if [ -f "$candidate" ]; then
		DOTENV=$candidate
		break
	fi
done
if [ -n "$DOTENV" ]; then
	set -a
	. "$DOTENV"
	set +a
fi

FORCE=0
ARGS=()
for arg in "$@"; do
	case "$arg" in
		--force|-f) FORCE=1 ;;
		*) ARGS+=("$arg") ;;
	esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

# ------------------------------------------------------------------ the map

# Pin the list to the branch tip. We are usually on a detached HEAD, and
# `rev-list HEAD` would then only see the stages up to wherever we are.
TIP=$(git rev-parse main 2>/dev/null || git rev-parse master 2>/dev/null || git rev-parse HEAD)

SHAS=()
TITLES=()
while IFS= read -r sha; do
	subject=$(git log -1 --pretty=%s "$sha")
	case "$subject" in
		stage\ *) SHAS+=("$sha"); TITLES+=("$subject") ;;
	esac
done < <(git rev-list --reverse "$TIP")

COUNT=${#SHAS[@]}

if [ -t 1 ]; then
	B=$(tput bold); D=$(tput dim); R=$(tput sgr0)
else
	B=; D=; R=
fi

here() {  # index of HEAD in the list, or "none"
	local head i
	head=$(git rev-parse HEAD)
	i=0
	while [ "$i" -lt "$COUNT" ]; do
		if [ "${SHAS[$i]}" = "$head" ]; then echo "$i"; return; fi
		i=$((i + 1))
	done
	echo none
}

need_stage() {
	local i
	i=$(here)
	if [ "$i" = none ]; then
		echo "HEAD is not a stage commit. Try: bash present.sh 1"
		exit 1
	fi
	echo "$i"
}

guard() {
	local dirt
	dirt=$(git status --porcelain --untracked-files=no)
	[ -z "$dirt" ] && return 0

	echo "${B}uncommitted changes:${R}"
	printf '%s\n' "$dirt" | sed 's/^/  /'
	if [ "$FORCE" = 1 ]; then
		echo "  discarding them (-f)"
		git checkout -- .
		return 0
	fi
	echo
	echo "Refusing to switch over them. Either:"
	echo "  git stash                      keep the edits"
	echo "  bash present.sh <stage> -f     throw them away"
	exit 1
}

banner() {
	local i=$1
	local sha=${SHAS[$1]}
	echo
	echo "${B}${TITLES[$i]}${R}   ${D}$((i + 1))/$COUNT  ${sha:0:8}${R}"
	echo
	git show --stat --format="" "$sha" | sed 's/^/  /'
	echo
	echo "${D}  diff: ./present.sh diff    next: ./present.sh next    run: ./present.sh run${R}"
	echo
}

goto() {
	guard
	git -c advice.detachedHead=false checkout -q "${SHAS[$1]}"
	banner "$1"
}

# --------------------------------------------------------------- the commands

cmd=${1:-list}

case "$cmd" in
	list)
		i=0
		while [ "$i" -lt "$COUNT" ]; do
			printf '%2d  %s  %s\n' "$((i + 1))" "${SHAS[$i]:0:8}" "${TITLES[$i]}"
			i=$((i + 1))
		done
		echo
		echo "  ./present.sh <n>   go to commit n   (./present.sh next also works)"
		;;

	next|prev)
		i=$(need_stage)
		if [ "$cmd" = next ]; then i=$((i + 1)); else i=$((i - 1)); fi
		if [ "$i" -lt 0 ] || [ "$i" -ge "$COUNT" ]; then
			echo "no stage $cmd from here"
			exit 1
		fi
		goto "$i"
		;;

	diff)
		git show --format=fuller "${SHAS[$(need_stage)]}"
		;;

	files)
		git show --name-only --format="" "${SHAS[$(need_stage)]}"
		;;

	show)
		if [ $# -lt 2 ]; then echo "usage: bash present.sh show <file>"; exit 1; fi
		git show "${SHAS[$(need_stage)]}:$2"
		;;

	run)
		i=$(need_stage)

		# Stages 1-8 read BASE_URL / API_KEY from the environment. Prefer the
		# documented .env name, but accept the existing env file too.
		ENVFILE=()
		if [ -f .agents/.env ]; then
			ENVFILE=(--env-file .agents/.env)
		elif [ -f .agents/env ]; then
			ENVFILE=(--env-file .agents/env)
		fi

		if [ "$i" -le 3 ]; then
			echo "${D}uv run llm.py${R}"
			uv run ${ENVFILE[@]+"${ENVFILE[@]}"} llm.py
		elif [ "$i" -le 7 ]; then
			echo "${D}uv run agent.py${R}"
			uv run ${ENVFILE[@]+"${ENVFILE[@]}"} agent.py
		else
			if [ ! -f "$HOME/.agents/env" ]; then
				echo "stage 9+ reads ~/.agents/env, which does not exist yet."
				echo "run: bash present.sh setup"
				exit 1
			fi
			echo "${D}uv run neuralcode${R}"
			uv run neuralcode
		fi
		;;

	setup)
		if [ -f "$HOME/.agents/env" ]; then
			echo "$HOME/.agents/env already exists, leaving it alone:"
			sed 's/=.*/=<set>/' "$HOME/.agents/env" | sed 's/^/  /'
			exit 0
		fi
		SOURCE_ENV=
		if [ -f .agents/.env ]; then
			SOURCE_ENV=.agents/.env
		elif [ -f .agents/env ]; then
			SOURCE_ENV=.agents/env
		fi
		if [ -z "$SOURCE_ENV" ]; then
			echo "no .agents/.env or .agents/env to copy from"
			exit 1
		fi
		mkdir -p "$HOME/.agents"
		cp "$SOURCE_ENV" "$HOME/.agents/env"
		echo "wrote $HOME/.agents/env"
		;;

	main)
		guard
		git -c advice.detachedHead=false checkout -q main
		echo "back on main"
		;;

	help|-h|--help)
		sed -n '2,17p' "$0" | sed 's/^#\{1,2\} \{0,1\}//'
		;;

	*)
		if [ -n "${cmd//[0-9]/}" ]; then
			echo "unknown command: $cmd   (try: bash present.sh list)"
			exit 1
		fi
		if [ "$cmd" -lt 1 ] || [ "$cmd" -gt "$COUNT" ]; then
			echo "no stage $cmd (1..$COUNT)"
			exit 1
		fi
		goto $((cmd - 1))
		;;
esac
