int nested_value(int value) {
    if (value > 0) {
        if (value > 1) {
            if (value > 2) {
                return value;
            }
        }
    }
    return 0;
}
