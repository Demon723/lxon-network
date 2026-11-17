#!/usr/bin/env bash
# Where is i-09ea5a833cbf52360? Check every enabled region of the account, honestly.
# Written as a file because nested quoting in `bash -c` and zsh's lack of word splitting were
# producing output that looked like a result but was not one.
set -uo pipefail
PROFILE="${1:-lxon-remote}"
TARGET="${2:-i-09ea5a833cbf52360}"

echo "profile : $PROFILE"
echo "identity: $(aws sts get-caller-identity --profile "$PROFILE" --query 'Account' --output text 2>&1)"
echo "target  : $TARGET"
echo

aws ec2 describe-regions --profile "$PROFILE" --query 'Regions[].RegionName' --output text \
  | tr '\t' '\n' > /tmp/lxon-regions.txt

total=0
scanned=0
hits=0
while IFS= read -r r; do
  [ -n "$r" ] || continue
  scanned=$((scanned + 1))
  # `length(reservations[].instances[])` is INVALID JMESPath on a nested projection: it raised
  # an error for every region including the one that actually held the instance, and the loop
  # then reported "visible instances: 0". A check that cannot fail is not a check. Count ids
  # from a projection instead, and keep the direct lookup below as the authority.
  ids=$(aws ec2 describe-instances --profile "$PROFILE" --region "$r" \
          --query 'Reservations[].Instances[].InstanceId' --output text 2>&1)
  case "$ids" in
    *ERROR*) printf '  %-18s unreadable: %s\n' "$r" "$(echo "$ids" | tr '\n' ' ' | cut -c1-60)" ;;
    '')      printf '  %-18s 0 instance(s)\n' "$r" ;;
    *)
      n=$(echo "$ids" | wc -w | tr -d ' ')
      printf '  %-18s %s instance(s): %s\n' "$r" "$n" "$(echo "$ids" | tr '\n' ' ')"
      total=$((total + n))
      ;;
  esac
  # direct lookup, so an ID in a region we cannot enumerate is still caught
  if aws ec2 describe-instances --profile "$PROFILE" --region "$r" \
       --instance-ids "$TARGET" >/dev/null 2>&1; then
    printf '     >>> %s FOUND in %s\n' "$TARGET" "$r"
    hits=$((hits + 1))
  fi
done < /tmp/lxon-regions.txt

echo
echo "regions scanned : $scanned"
echo "visible instances in account: $total"
echo "matches for $TARGET: $hits"
rm -f /tmp/lxon-regions.txt
[ "$hits" -gt 0 ] && exit 0
exit 3
