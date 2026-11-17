#include "utils/type_system.h"

const char *type_name(DataType t) {
    switch (t) {
        case TYPE_INT:
            return "int";
        case TYPE_FLOAT:
            return "float";
        case TYPE_STRING:
            return "string";
        case TYPE_VOID:
            return "void";
        default:
            return "erro";
    }
}

int is_numeric(DataType t) {
    return (t == TYPE_INT || t == TYPE_FLOAT);
}

int is_assignable(DataType lhs, DataType rhs) {
    if (lhs == TYPE_ERROR || rhs == TYPE_ERROR) return 1;
    if (lhs == rhs) return 1;
    if (lhs == TYPE_FLOAT && rhs == TYPE_INT) return 1; /* int -> float promotion */
    return 0;
}
