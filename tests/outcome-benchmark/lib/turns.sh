# Shared feature request and turn scripts for tests/outcome-benchmark's
# two conditions. Sourced by run-trial.sh. Pure data -- no functions.

FEATURE_REQUEST="I want to build a small URL shortener, implemented in Python using only the standard library. Two components: a public redirect service that takes a short code and 302-redirects to the original URL, and an admin API for creating new short links (POST with a target URL, returns a short code). Both read/write the same data store (short code -> target URL mapping). Redirect latency matters -- it's on the hot path for every click. No user accounts, no analytics, no custom short codes (always generated). That's the complete design -- no open questions on my end."

# treatment: brainstorming -> architecture-gate -> program-design-gate ->
# writing-plans -> vertical-slices-gate (12 turns, verbatim from
# tests/gate-quality/vertical-slices-gate/run-trial.sh)
TREATMENT_TURNS=(
    "$FEATURE_REQUEST"
    "That approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed."
    "That architecture approach looks good -- please continue."
    "Approved. Please write the architecture doc."
    "I've reviewed the architecture doc, it looks good, please proceed."
    "Approved. Please write the program design doc."
    "I've reviewed the program design doc, it looks good, please proceed."
    "Approved. Please write the implementation plan."
    "I've reviewed the plan, it looks good."
    "Confirmed, that build order looks right."
)

# baseline: brainstorming -> writing-plans only, no factory-gates loaded
BASELINE_TURNS=(
    "$FEATURE_REQUEST"
    "That approach looks good -- please continue."
    "Approved. Please write the spec and commit it."
    "I've reviewed the spec, it looks good, please proceed to plan the implementation."
    "That implementation approach looks good -- please write the plan."
    "I've reviewed the plan, it looks good."
)
