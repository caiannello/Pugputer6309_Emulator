/* math.h: each function against its exact value (worked out on the PC, for
   the float the argument becomes), within a few units in the last place; and
   the exact ones (floor and the rest, sqrt, frexp, ldexp) printed. */
#include <stdio.h>
#include <math.h>

static int bad, checked;

static void near(const char *what, double got, double want)
{
    double d = got - want, m = want < 0 ? -want : want;
    if (d < 0)
        d = -d;
    checked++;
    if (d > 6e-7 * (m > 1 ? m : 1)) {
        printf("%s: %.9g, not %.9g\n", what, got, want);
        bad++;
    }
}

int main(void)
{
    int e;
    double ip;

    near("sin", sin(0.5), 0.4794255386);
    near("sin", sin(-1.0), -0.8414709848);
    near("sin", sin(2.0), 0.9092974268);
    near("sin", sin(3.14159265), -8.742278e-08);
    near("sin", sin(10.0), -0.5440211109);
    near("sin", sin(100.0), -0.5063656411);
    near("sin", sin(0.001), 0.0009999998808);
    near("sin", sin(0.7853981), 0.7071067545);
    near("cos", cos(0.0), 1);
    near("cos", cos(0.5), 0.8775825619);
    near("cos", cos(-1.0), 0.5403023059);
    near("cos", cos(2.0), -0.4161468365);
    near("cos", cos(3.14159265), -1);
    near("cos", cos(10.0), -0.8390715291);
    near("cos", cos(100.0), 0.8623188723);
    near("tan", tan(0.5), 0.5463024898);
    near("tan", tan(-1.0), -1.557407725);
    near("tan", tan(1.5), 14.10141995);
    near("tan", tan(3.0), -0.1425465431);
    near("tan", tan(0.7853981), 0.9999999245);
    near("asin", asin(0.0), 0);
    near("asin", asin(0.25), 0.2526802551);
    near("asin", asin(-0.5), -0.5235987756);
    near("asin", asin(0.75), 0.848062079);
    near("asin", asin(1.0), 1.570796327);
    near("asin", asin(-0.99), -1.429256921);
    near("acos", acos(0.0), 1.570796327);
    near("acos", acos(0.25), 1.318116072);
    near("acos", acos(-0.5), 2.094395102);
    near("acos", acos(0.75), 0.7227342478);
    near("acos", acos(1.0), 0);
    near("acos", acos(-0.99), 3.000053248);
    near("atan", atan(0.0), 0);
    near("atan", atan(0.3), 0.2914568054);
    near("atan", atan(-1.0), -0.7853981634);
    near("atan", atan(2.0), 1.107148718);
    near("atan", atan(10.0), 1.471127674);
    near("atan", atan(-1000.0), -1.569796327);
    near("atan2", atan2(1.0, 1.0), 0.7853981634);
    near("atan2", atan2(1.0, -1.0), 2.35619449);
    near("atan2", atan2(-1.0, -1.0), -2.35619449);
    near("atan2", atan2(-1.0, 1.0), -0.7853981634);
    near("atan2", atan2(0.0, -1.0), 3.141592654);
    near("atan2", atan2(3.0, 4.0), 0.6435011088);
    near("exp", exp(0.0), 1);
    near("exp", exp(1.0), 2.718281828);
    near("exp", exp(-1.0), 0.3678794412);
    near("exp", exp(2.5), 12.18249396);
    near("exp", exp(10.0), 22026.46579);
    near("exp", exp(-10.0), 4.539992976e-05);
    near("exp", exp(50.0), 5.184705529e+21);
    near("exp", exp(-50.0), 1.928749848e-22);
    near("log", log(1.0), 0);
    near("log", log(2.0), 0.6931471806);
    near("log", log(0.5), -0.6931471806);
    near("log", log(10.0), 2.302585093);
    near("log", log(1e-05), -11.51292549);
    near("log", log(12345.0), 9.421006402);
    near("log", log(1e+30), 69.0775528);
    near("log10", log10(1.0), 0);
    near("log10", log10(2.0), 0.3010299957);
    near("log10", log10(1000.0), 3);
    near("log10", log10(1e-05), -5.000000011);
    near("log10", log10(12345.0), 4.091491094);
    near("pow", pow(2.0, 10.0), 1024);
    near("pow", pow(2.0, 0.5), 1.414213562);
    near("pow", pow(10.0, -2.0), 0.01);
    near("pow", pow(-2.0, 3.0), -8);
    near("pow", pow(-2.0, 4.0), 16);
    near("pow", pow(1.5, 2.5), 2.755675961);
    near("pow", pow(9.0, 0.5), 3);
    near("pow", pow(2.0, -1.0), 0.5);
    near("sqrt", sqrt(2.0), 1.414213562);
    near("sqrt", sqrt(0.25), 0.5);
    near("sqrt", sqrt(10.0), 3.16227766);
    near("sqrt", sqrt(1e-20), 9.999999841e-11);
    near("sqrt", sqrt(1e+30), 1.000000008e+15);
    near("sqrt", sqrt(12345.678), 111.1111054);
    near("sinh", sinh(0.0), 0);
    near("sinh", sinh(0.5), 0.5210953055);
    near("sinh", sinh(-1.0), -1.175201194);
    near("sinh", sinh(3.0), 10.01787493);
    near("cosh", cosh(0.0), 1);
    near("cosh", cosh(0.5), 1.127625965);
    near("cosh", cosh(-1.0), 1.543080635);
    near("cosh", cosh(3.0), 10.067662);
    near("tanh", tanh(0.0), 0);
    near("tanh", tanh(0.3), 0.2913126234);
    near("tanh", tanh(-1.0), -0.761594156);
    near("tanh", tanh(3.0), 0.9950547537);
    near("tanh", tanh(20.0), 1);
    printf("%d checked, %d off\n", checked, bad);

    printf("floor %g %g %g %g\n", floor(2.7), floor(-2.7), floor(-3.0), floor(0.2));
    printf("ceil %g %g %g %g\n", ceil(2.2), ceil(-2.7), ceil(5.0), ceil(-0.2));
    printf("trunc %g %g round %g %g %g %g\n", trunc(2.7), trunc(-2.7), round(2.5), round(-2.5), round(2.49), round(-0.4));
    printf("fabs %g %g fmod %g %g\n", fabs(-3.5), fabs(2.0), fmod(7.5, 2.0), fmod(-7.5, 2.0));
    printf("modf %g", modf(3.75, &ip));
    printf(" %g", ip);
    printf(" frexp %g", frexp(48.0, &e));
    printf(" %d ldexp %g %g\n", e, ldexp(0.75, 6), ldexp(1.0, -3));
    printf("sqrt %.9g %g %g %g\n", sqrt(2.0), sqrt(16.0), sqrt(0.0), sqrt(-1.0));
    printf("edges %g %g %g %g %g\n", log(0.0), log(-1.0), exp(100.0), exp(-100.0), asin(2.0));
    printf("pi %.7f %.7f\n", M_PI, 4 * atan(1.0));
    return 0;
}
