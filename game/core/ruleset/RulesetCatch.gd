extends RefCounted
class_name RulesetCatch
## The catch-module interface (ADR-018 §1): ball + target state → caught / shake count.
## gh #34 migrates Battle.gd's _attempt_catch (and the safari variant) behind it,
## pinning the method signatures as they land.
