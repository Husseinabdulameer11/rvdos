/* Freestanding test program -- no globals, no libc, integer only.
   Sum of squares 1..5 = 1+4+9+16+25 = 55, via a real function call in a
   loop, exercising the hardware multiplier (rv32im target). */

static int square(int x) {
    return x * x;
}

int main(void) {
    int sum = 0;
    for (int i = 1; i <= 5; i++) {
        sum += square(i);
    }
    return sum;
}
