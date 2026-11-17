#ifndef UTILS_TYPE_SYSTEM_H
#define UTILS_TYPE_SYSTEM_H

#include "utils/types.h"

/* Human-readable name of a data type (used in diagnostics and dumps). */
const char *type_name(DataType t);

/* True when the type participates in arithmetic/relational operations. */
int is_numeric(DataType t);

/* True when a value of type `rhs` may be assigned to a target of type `lhs`
 * (allows the implicit int -> float promotion). */
int is_assignable(DataType lhs, DataType rhs);

#endif /* UTILS_TYPE_SYSTEM_H */
