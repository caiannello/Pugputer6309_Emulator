/* math.h -- CC (the Pugputer's C compiler): double is float (IEEE single),
   so these are the float functions: good to about 7 significant digits (sqrt
   correctly rounded). They're in LIBC.A (no -lm), each module linked only if
   it's used. sin, cos and tan lose accuracy beyond some thousands. */
#ifndef _MATH_H
#define _MATH_H

#define HUGE_VAL (1e30 * 1e30)
#define INFINITY HUGE_VAL
#define NAN (0.0 / 0.0)
#define M_E 2.7182818284590452354
#define M_LOG2E 1.4426950408889634074
#define M_LOG10E 0.43429448190325182765
#define M_LN2 0.69314718055994530942
#define M_LN10 2.30258509299404568402
#define M_PI 3.14159265358979323846
#define M_PI_2 1.57079632679489661923
#define M_PI_4 0.78539816339744830962
#define M_1_PI 0.31830988618379067154
#define M_2_PI 0.63661977236758134308
#define M_SQRT2 1.41421356237309504880
#define M_SQRT1_2 0.70710678118654752440

double sin(double x);
double cos(double x);
double tan(double x);
double asin(double x);
double acos(double x);
double atan(double x);
double atan2(double y, double x);
double sinh(double x);
double cosh(double x);
double tanh(double x);
double exp(double x);
double log(double x);
double log10(double x);
double pow(double x, double y);
double sqrt(double x);
double fabs(double x);
double floor(double x);
double ceil(double x);
double trunc(double x);
double round(double x);
double fmod(double x, double y);
double modf(double x, double *ip);
double frexp(double x, int *e);
double ldexp(double x, int n);

/* The float names (C99's), the same functions. */
#define sinf sin
#define cosf cos
#define tanf tan
#define asinf asin
#define acosf acos
#define atanf atan
#define atan2f atan2
#define sinhf sinh
#define coshf cosh
#define tanhf tanh
#define expf exp
#define logf log
#define log10f log10
#define powf pow
#define sqrtf sqrt
#define fabsf fabs
#define floorf floor
#define ceilf ceil
#define truncf trunc
#define roundf round
#define fmodf fmod

#endif
