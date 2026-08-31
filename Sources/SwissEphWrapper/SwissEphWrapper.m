//
//  SwissEphWrapper.m
//  NityaPanchangam
//

#import "SwissEphWrapper.h"
#import "swephexp.h"

@implementation SwissEphWrapper

// Purnimanta tithi (1–30): Krishna Paksha 1–15, then Shukla Paksha 16–30.
//   1  = Krishna Pratipada  …  15 = Amavasya
//   16 = Shukla Pratipada   …  30 = Purnima
// Formula: shift elongation by 180° so that Purnima (180°) maps to the start of
// Krishna Paksha (tithi 1), then bucket into 12° slots.
- (int)calculateTithiNumberForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    double sunPosition[6], moonPosition[6];
    char errorMessage[256];
    swe_calc_ut(jd, SE_SUN,  SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPosition, errorMessage);
    swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPosition, errorMessage);
    double e = moonPosition[0] - sunPosition[0];
    if (e < 0) e += 360.0;
    return ((int)((e + 180.0) / 12.0) % 30) + 1;
}

- (NSDictionary *)calculateTithiForDate:(NSDate *)date latitude:(double)latitude longitude:(double)longitude {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [calendar setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:date];
    double hourDecimal = components.hour + (components.minute / 60.0) + (components.second / 3600.0);
    double julianDayUTC = swe_julday((int)components.year, (int)components.month, (int)components.day, hourDecimal, SE_GREG_CAL);
    double sunPosition[6], moonPosition[6];
    char errorMessage[256];
    swe_calc_ut(julianDayUTC, SE_SUN, SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPosition, errorMessage);
    swe_calc_ut(julianDayUTC, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPosition, errorMessage);
    double sunLong = sunPosition[0];
    double moonLong = moonPosition[0];
    double angleDifference = moonLong - sunLong;
    if (angleDifference < 0) { angleDifference += 360.0; }
    int tithiNumber = ((int)((angleDifference + 180.0) / 12.0) % 30) + 1;
    double nakshatraLength = 360.0 / 27.0;
    int nakshatraNumber = (int)(moonLong / nakshatraLength) + 1;
    double combinedLong = sunLong + moonLong;
    if (combinedLong >= 360.0) { combinedLong -= 360.0; }
    int yogaNumber = (int)(combinedLong / nakshatraLength) + 1;
    int karanaNumber = (int)(angleDifference / 6.0) + 1;
    double searchJD = julianDayUTC;
    int currentTithi = tithiNumber;
    double stepInterval = 15.0 / 1440.0;
    while (currentTithi == tithiNumber) {
        searchJD += stepInterval;
        currentTithi = [self calculateTithiNumberForJulianDay:searchJD];
        if (searchJD > julianDayUTC + 2.0) { break; }
    }
    return @{
        @"julianDay":       @(julianDayUTC),
        @"tithiEndJD":      @(searchJD),
        @"tithiNumber":     @(tithiNumber),
        @"nakshatraNumber": @(nakshatraNumber),
        @"yogaNumber":      @(yogaNumber),
        @"karanaNumber":    @(karanaNumber)
    };
}

- (NSDictionary *)calculateSunriseSunsetForDate:(NSDate *)date latitude:(double)latitude longitude:(double)longitude {
    swe_set_topo(longitude, latitude, 0);
    NSCalendar *localCalendar = [NSCalendar currentCalendar];
    NSDate *startOfLocalDay = [localCalendar startOfDayForDate:date];
    double jd_startOfLocalDay = [self getJulianDayUTCFromDate:startOfLocalDay];

    double riseTret[3]     = {0.0, 0.0, 0.0};
    double setTret[3]      = {0.0, 0.0, 0.0};
    double moonRiseTret[3] = {0.0, 0.0, 0.0};
    double moonSetTret[3]  = {0.0, 0.0, 0.0};

    char errorMessage[256];
    char starname[] = "";
    double geopos[3] = {longitude, latitude, 0.0};

    swe_rise_trans(jd_startOfLocalDay, SE_SUN,  starname, SEFLG_SWIEPH, SE_CALC_RISE, geopos, 0.0, 0.0, riseTret,     errorMessage);
    swe_rise_trans(jd_startOfLocalDay, SE_SUN,  starname, SEFLG_SWIEPH, SE_CALC_SET,  geopos, 0.0, 0.0, setTret,      errorMessage);
    swe_rise_trans(jd_startOfLocalDay, SE_MOON, starname, SEFLG_SWIEPH, SE_CALC_RISE, geopos, 0.0, 0.0, moonRiseTret, errorMessage);
    swe_rise_trans(jd_startOfLocalDay, SE_MOON, starname, SEFLG_SWIEPH, SE_CALC_SET,  geopos, 0.0, 0.0, moonSetTret,  errorMessage);

    return @{
        @"sunriseJD":  @(riseTret[0]),
        @"sunsetJD":   @(setTret[0]),
        @"moonriseJD": @(moonRiseTret[0]),
        @"moonsetJD":  @(moonSetTret[0])
    };
}

// Newton-Raphson helper: refines an approximate Purnima JD (elongation = 180°).
// Converges in 5-7 iterations (synodic variability can cause up to ~12 h linear error).
static double refinePurnimaJD(SwissEphWrapper *self, double approxJD) {
    char errorMessage[256];
    double sunPos[6], moonPos[6];
    double purnimaJD = approxJD;
    for (int i = 0; i < 10; i++) {
        if (swe_calc_ut(purnimaJD, SE_SUN,  SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPos,  errorMessage) < 0) break;
        if (swe_calc_ut(purnimaJD, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPos, errorMessage) < 0) break;
        double e = moonPos[0] - sunPos[0];
        if (e < 0)    e += 360.0;
        double err = e - 180.0;
        if (err >  180.0) err -= 360.0;
        if (err < -180.0) err += 360.0;
        double correction = err * (29.53059 / 360.0);
        purnimaJD -= correction;
        if (fabs(correction) < 0.00001) break;
    }
    return purnimaJD;
}

// Newton-Raphson helper: refines an approximate Amavasya JD (elongation = 0°).
static double refineAmavasyaJD(SwissEphWrapper *self, double approxJD) {
    char errorMessage[256];
    double sunPos[6], moonPos[6];
    double amavJD = approxJD;
    for (int i = 0; i < 10; i++) {
        if (swe_calc_ut(amavJD, SE_SUN,  SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPos,  errorMessage) < 0) break;
        if (swe_calc_ut(amavJD, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPos, errorMessage) < 0) break;
        double e = moonPos[0] - sunPos[0];
        if (e < 0) e += 360.0;
        // Wrap to (−180, 180] so the correction direction is always correct near 0°/360°.
        if (e > 180.0) e -= 360.0;
        double correction = e * (29.53059 / 360.0);
        amavJD -= correction;
        if (fabs(correction) < 0.00001) break;
    }
    return amavJD;
}

/// Solar (Saura Mana): month = Sun's current sidereal rashi.
/// Same formula as the Purnimanta/Amanta but uses the Sun's position RIGHT NOW,
/// not at a Purnima. Mesha(Aries)→Vaishakha(2) … Meena(Pisces)→Chaitra(1).
/// Solar (Saura Mana): month = Sun's current sidereal rashi.
/// Same formula as the Purnimanta/Amanta but uses the Sun's position RIGHT NOW,
/// not at a Purnima. Mesha(Aries)→Vaishakha(2) … Meena(Pisces)→Chaitra(1).
- (int)calculateLunarMonthForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    char errorMessage[256];
    double sunPos[6];
    if (swe_calc_ut(jd, SE_SUN, SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPos, errorMessage) < 0) return 0;
    int rashi = (int)(sunPos[0] / 30.0);   // 0=Mesha … 11=Meena
    return ((rashi + 1) % 12) + 1;         // Mesha→2(Vaishakha) … Meena→1(Chaitra)
}

// THE SOURCE OF TRUTH HELPER
// Calculates the true Amanta month and leap status for any given moment.
static void getAmantaMonthDetails(SwissEphWrapper *self, double jd, int *monthIndex, BOOL *isAdhik) {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    char errorMessage[256];
    double sunPos[6], moonPos[6];
    swe_calc_ut(jd, SE_SUN,  SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPos,  errorMessage);
    swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPos, errorMessage);

    double elongation = moonPos[0] - sunPos[0];
    if (elongation < 0) elongation += 360.0;
    
    // Find the Amavasya that ends this month, and the Amavasya that started it
    double degreesToNextAmav = 360.0 - elongation;
    if (degreesToNextAmav < 0.5) degreesToNextAmav = 360.0; // boundary safety
    
    double daysAhead = degreesToNextAmav * 29.53059 / 360.0;
    double nextAmavJD = refineAmavasyaJD(self, jd + daysAhead);
    double prevAmavJD = refineAmavasyaJD(self, nextAmavJD - 29.53059);

    // Get the Sun's Rashi at both boundaries
    double sunAtNext[6], sunAtPrev[6];
    swe_calc_ut(nextAmavJD, SE_SUN, SEFLG_SWIEPH | SEFLG_SIDEREAL, sunAtNext, errorMessage);
    swe_calc_ut(prevAmavJD, SE_SUN, SEFLG_SWIEPH | SEFLG_SIDEREAL, sunAtPrev, errorMessage);

    int rashiNext = (int)(sunAtNext[0] / 30.0);
    int rashiPrev = (int)(sunAtPrev[0] / 30.0);

    // The core Vedic definition of Leap vs Regular months (Zero Sankranti)
    if (rashiNext == rashiPrev) {
        *isAdhik = YES;
        *monthIndex = ((rashiNext + 2 - 1) % 12) + 1; // Takes name of upcoming transit
    } else {
        *isAdhik = NO;
        *monthIndex = ((rashiNext + 1 - 1) % 12) + 1; // Takes name of completed transit
    }
}

/// Purnimanta: month = Sun's rashi at the NEXT upcoming Purnima.
/// In Purnimanta, a month spans Krishna Paksha first then Shukla Paksha, and is
/// named after the Purnima that CLOSES it. Therefore the month is always
/// determined by the UPCOMING Purnima, regardless of current paksha.
/// Purnimanta Month Calculator
/// Purnimanta Month Calculator
- (int)calculatePurnimantaMonthForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    char errorMessage[256];
    double sunPos[6], moonPos[6];
    if (swe_calc_ut(jd, SE_SUN,  SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPos,  errorMessage) < 0) return 0;
    if (swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPos, errorMessage) < 0) return 0;
    
    double elongation = moonPos[0] - sunPos[0];
    if (elongation < 0) elongation += 360.0;
    
    int currentMonth;
    BOOL currentIsAdhik;
    getAmantaMonthDetails(self, jd, &currentMonth, &currentIsAdhik);
    
    if (elongation >= 180.0) {
        // KRISHNA PAKSHA: Takes the month name of the NEXT Amanta month
        double degreesToNextAmav = 360.0 - elongation;
        double daysToAmav = degreesToNextAmav * 29.53059 / 360.0;
        double nextMonthJD = jd + daysToAmav + 5.0; // Safely lands in next Shukla Paksha
        
        int nextMonth;
        BOOL nextIsAdhik;
        getAmantaMonthDetails(self, nextMonthJD, &nextMonth, &nextIsAdhik);
        return nextMonth;
    } else {
        // SHUKLA PAKSHA: Takes the month name of the CURRENT Amanta month
        return currentMonth;
    }
}

/// Adhik Maas: no solar Sankranti occurred between the bracketing Amavasyas (new moons).
/// Traditional definition (used by all panchangs for both Amanta and Purnimanta display):
/// if the Sun stays in the same rashi from one Amavasya to the next, the month is Adhik.
/// Using Purnima boundaries instead would miss 2026 Adhik Jyeshtha (May 17 – Jun 15).
/// Amanta Adhik Maas Flag
- (BOOL)calculateIsAdhikMaasForJulianDay:(double)jd {
    int currentMonth;
    BOOL currentIsAdhik;
    getAmantaMonthDetails(self, jd, &currentMonth, &currentIsAdhik);
    return currentIsAdhik;
}

/// Purnimanta Adhik Maas: a Purnimanta month is Adhik when the UPCOMING PURNIMA
/// (which closes the month) falls inside an Amanta Adhik window.
/// This is different from the Amanta check — the Purnimanta Adhik period ends at the
/// Purnima, so the next Purnimanta month gets a full ~29 days.
//- (BOOL)calculateIsPurnimantaAdhikMaasForJulianDay:(double)jd {
//    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
//    char errorMessage[256];
//    double sunPos[6], moonPos[6];
//    if (swe_calc_ut(jd, SE_SUN,  SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPos,  errorMessage) < 0) return NO;
//    if (swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPos, errorMessage) < 0) return NO;
//    double elongation = moonPos[0] - sunPos[0];
//    if (elongation < 0) elongation += 360.0;
//    double degreesToNext = fmod(180.0 - elongation + 360.0, 360.0);
//    double daysAhead     = degreesToNext * 29.53059 / 360.0;
//    double nextPurnimaJD = refinePurnimaJD(self, jd + daysAhead);
//    return [self calculateIsAdhikMaasForJulianDay:nextPurnimaJD];
//}

/// Purnimanta Adhik Maas Flag
- (BOOL)calculateIsPurnimantaAdhikMaasForJulianDay:(double)jd {
    int currentMonth;
    BOOL currentIsAdhik;
    
    // CRITICAL FIX: In Purnimanta, BOTH halves (Shukla and Krishna) inherit
    // the Adhik status of the CURRENT underlying Amanta month!
    getAmantaMonthDetails(self, jd, &currentMonth, &currentIsAdhik);
    return currentIsAdhik;
}

/// Amanta month — a thin wrapper over the same source-of-truth helper
/// Purnimanta and the Amanta Adhik flag already call, so all three can never
/// disagree with each other.
- (int)calculateAmantaMonthForJulianDay:(double)jd {
    int month;
    BOOL isAdhik;
    getAmantaMonthDetails(self, jd, &month, &isAdhik);
    return month;
}

- (double)getJulianDayUTCFromDate:(NSDate *)date {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    [calendar setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
    NSDateComponents *components = [calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:date];
    double hourDecimal = components.hour + (components.minute / 60.0) + (components.second / 3600.0);
    return swe_julday((int)components.year, (int)components.month, (int)components.day, hourDecimal, SE_GREG_CAL);
}

- (NSDictionary *)calculateMuhuratsWithSunrise:(double)sunriseJD sunset:(double)sunsetJD weekday:(int)weekday {
    double dayDuration    = sunsetJD - sunriseJD;
    double muhuratLength15 = dayDuration / 15.0;
    double muhuratLength8  = dayDuration / 8.0;

    // ── Abhijit (8th of 15) ───────────────────────────────────────────────
    double abhijitStart = sunriseJD + 7.0 * muhuratLength15;
    double abhijitEnd   = abhijitStart + muhuratLength15;

    // ── Vijaya (10th of 15) ───────────────────────────────────────────────
    double vijayaStart = sunriseJD + 9.0 * muhuratLength15;
    double vijayaEnd   = vijayaStart + muhuratLength15;

    // ── Rahu / Yama / Gulik (1/8 segments by weekday) ────────────────────
    int rahuSegments[7]  = {8, 2, 7, 5, 6, 4, 3};
    int yamaSegments[7]  = {5, 4, 3, 2, 7, 6, 1};
    int gulikSegments[7] = {6, 5, 4, 3, 2, 1, 7};
    double rahuStart  = sunriseJD + (rahuSegments[weekday  - 1] - 1) * muhuratLength8;
    double rahuEnd    = rahuStart  + muhuratLength8;
    double yamaStart  = sunriseJD + (yamaSegments[weekday  - 1] - 1) * muhuratLength8;
    double yamaEnd    = yamaStart  + muhuratLength8;
    double gulikStart = sunriseJD + (gulikSegments[weekday - 1] - 1) * muhuratLength8;
    double gulikEnd   = gulikStart + muhuratLength8;

    // ── Brahma Muhurat: 96–48 minutes before sunrise ─────────────────────
    double brahmaStart = sunriseJD - (96.0 / 1440.0);
    double brahmaEnd   = sunriseJD - (48.0 / 1440.0);

    // ── Amrit Kaal (Chaughadia Amrit, daytime) ────────────────────────────
    // Amrit segment position (0-indexed) per weekday: Sun=3,Mon=0,Tue=5,Wed=1,Thu=6,Fri=2,Sat=7
    int amritSegments[7] = {3, 0, 5, 1, 6, 2, 7};
    double amritStart = sunriseJD + amritSegments[weekday - 1] * muhuratLength8;
    double amritEnd   = amritStart + muhuratLength8;

    // ── Godhuli Muhurat: 24 min around sunset ─────────────────────────────
    double godhuliStart = sunsetJD - (24.0 / 1440.0);
    double godhuliEnd   = sunsetJD + (24.0 / 1440.0);

    return @{
        @"abhijitStart":  @(abhijitStart),  @"abhijitEnd":  @(abhijitEnd),
        @"vijayaStart":   @(vijayaStart),   @"vijayaEnd":   @(vijayaEnd),
        @"rahuStart":     @(rahuStart),     @"rahuEnd":     @(rahuEnd),
        @"yamaStart":     @(yamaStart),     @"yamaEnd":     @(yamaEnd),
        @"gulikStart":    @(gulikStart),    @"gulikEnd":    @(gulikEnd),
        @"brahmaStart":   @(brahmaStart),   @"brahmaEnd":   @(brahmaEnd),
        @"amritStart":    @(amritStart),    @"amritEnd":    @(amritEnd),
        @"godhuliStart":  @(godhuliStart),  @"godhuliEnd":  @(godhuliEnd),
    };
}

- (int)calculateMoonRashiForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    double moonPosition[6];
    char errorMessage[256];
    swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPosition, errorMessage);
    return (int)(moonPosition[0] / 30.0) + 1;
}

- (int)calculateNakshatraForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    double moonPosition[6];
    char errorMessage[256];
    swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPosition, errorMessage);
    return (int)(moonPosition[0] / 13.333333) + 1;
}

- (int)calculateYogaForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    double sunPosition[6], moonPosition[6];
    char errorMessage[256];
    swe_calc_ut(jd, SE_SUN, SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPosition, errorMessage);
    swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPosition, errorMessage);
    double totalLongitude = sunPosition[0] + moonPosition[0];
    if (totalLongitude >= 360.0) { totalLongitude -= 360.0; }
    return (int)(totalLongitude / 13.333333) + 1;
}

- (double)calculateNakshatraEndTimeForJulianDay:(double)startJD {
    int startingNakshatra = [self calculateNakshatraForJulianDay:startJD];
    double step = 15.0 / (24.0 * 60.0);
    double searchJD = startJD;
    int searchNakshatra = startingNakshatra;
    while (searchNakshatra == startingNakshatra) {
        searchJD += step;
        searchNakshatra = [self calculateNakshatraForJulianDay:searchJD];
        if (searchJD > startJD + 1.5) { break; }
    }
    return searchJD;
}

- (double)calculateYogaEndTimeForJulianDay:(double)startJD {
    int startingYoga = [self calculateYogaForJulianDay:startJD];
    double step = 15.0 / (24.0 * 60.0);
    double searchJD = startJD;
    int searchYoga = startingYoga;
    while (searchYoga == startingYoga) {
        searchJD += step;
        searchYoga = [self calculateYogaForJulianDay:searchJD];
        if (searchJD > startJD + 1.5) { break; }
    }
    return searchJD;
}

// Karana (half-tithi, 1–60 per lunar month) — same Sun/Moon elongation used by
// calculateTithiForDate:, just as a reusable per-instant primitive so a karana
// boundary can be searched for independently of a tithi calculation.
- (int)calculateKaranaForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    double sunPosition[6], moonPosition[6];
    char errorMessage[256];
    swe_calc_ut(jd, SE_SUN,  SEFLG_SWIEPH | SEFLG_SIDEREAL, sunPosition, errorMessage);
    swe_calc_ut(jd, SE_MOON, SEFLG_SWIEPH | SEFLG_SIDEREAL, moonPosition, errorMessage);
    double e = moonPosition[0] - sunPosition[0];
    if (e < 0) e += 360.0;
    return (int)(e / 6.0) + 1;
}

// A karana is half a tithi (~10–13h in practice), much shorter than a
// nakshatra/yoga — capped well below their 1.5-day search window.
- (double)calculateKaranaEndTimeForJulianDay:(double)startJD {
    int startingKarana = [self calculateKaranaForJulianDay:startJD];
    double step = 15.0 / (24.0 * 60.0);
    double searchJD = startJD;
    int searchKarana = startingKarana;
    while (searchKarana == startingKarana) {
        searchJD += step;
        searchKarana = [self calculateKaranaForJulianDay:searchJD];
        if (searchJD > startJD + 0.833) { break; }
    }
    return searchJD;
}

// MARK: - Navagraha (9 Planet) Positions

- (NSArray<NSDictionary *> *)calculatePlanetPositionsForJulianDay:(double)jd {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    long flags = SEFLG_SWIEPH | SEFLG_SIDEREAL;
    char errorMessage[256];
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:9];

    // SE planet IDs for the 7 classical planets
    int seIds[7] = { SE_SUN, SE_MOON, SE_MARS, SE_MERCURY, SE_JUPITER, SE_VENUS, SE_SATURN };

    for (int i = 0; i < 7; i++) {
        double pos[6];
        swe_calc_ut(jd, seIds[i], flags, pos, errorMessage);
        double lon = pos[0];
        while (lon <   0) lon += 360.0;
        while (lon >= 360) lon -= 360.0;
        int rashi = (int)(lon / 30.0) + 1;
        double deg = fmod(lon, 30.0);
        [result addObject:@{
            @"planetIndex": @(i),
            @"longitude":   @(lon),
            @"rashiNumber": @(rashi),
            @"degrees":     @(deg)
        }];
    }

    // Rahu — Mean North Node (index 7)
    double rahuPos[6];
    swe_calc_ut(jd, SE_MEAN_NODE, flags, rahuPos, errorMessage);
    double rahuLon = rahuPos[0];
    while (rahuLon <   0) rahuLon += 360.0;
    while (rahuLon >= 360) rahuLon -= 360.0;
    int rahuRashi = (int)(rahuLon / 30.0) + 1;
    [result addObject:@{
        @"planetIndex": @(7),
        @"longitude":   @(rahuLon),
        @"rashiNumber": @(rahuRashi),
        @"degrees":     @(fmod(rahuLon, 30.0))
    }];

    // Ketu — South Node = Rahu + 180° (index 8)
    double ketuLon = fmod(rahuLon + 180.0, 360.0);
    int ketuRashi = (int)(ketuLon / 30.0) + 1;
    [result addObject:@{
        @"planetIndex": @(8),
        @"longitude":   @(ketuLon),
        @"rashiNumber": @(ketuRashi),
        @"degrees":     @(fmod(ketuLon, 30.0))
    }];

    return [result copy];
}

// MARK: - Ascendant (Lagna)

- (double)calculateAscendantAtJD:(double)jd latitude:(double)lat longitude:(double)lon {
    swe_set_sid_mode(SE_SIDM_LAHIRI, 0, 0);
    double cusps[13] = {0};
    double ascmc[10] = {0};
    // Whole Sign houses — Vedic standard; ascmc[0] is the sidereal Ascendant degree
    swe_houses_ex(jd, SEFLG_SIDEREAL, lat, lon, 'W', cusps, ascmc);
    double asc = ascmc[0];
    while (asc <    0.0) asc += 360.0;
    while (asc >= 360.0) asc -= 360.0;
    return asc;
}

// MARK: - Eclipses (Grahan)
//
// Both use the *_when_loc variants rather than *_when_glob. The global search
// finds every eclipse on Earth; the local search finds only those actually
// visible from the given place and returns local contact times. That is the
// distinction the app needs, because Sutak is observed only where the eclipse
// is visible — reporting a Chilean eclipse to a user in Ujjain would imply an
// observance that does not apply.
//
// Swiss Ephemeris requires tret[10] and attr[20]; both are oversized here so a
// future flag that writes further into the arrays cannot overflow the stack.

- (nullable NSDictionary *)nextSolarEclipseVisibleFromJD:(double)startJD
                                                latitude:(double)lat
                                               longitude:(double)lon
                                             maxDaysAhead:(double)maxDays {
    // geopos is longitude-first, then latitude, then altitude in metres.
    double geopos[3] = { lon, lat, 0.0 };
    double tret[20]  = {0};
    double attr[20]  = {0};
    char errorMessage[256] = {0};

    int32 result = swe_sol_eclipse_when_loc(startJD, SEFLG_SWIEPH, geopos, tret, attr, 0, errorMessage);
    if (result < 0) { return nil; }

    double maxJD = tret[0];
    // The local search will happily run years ahead to find a visible eclipse;
    // anything past the caller's window is not an answer they asked for.
    if (maxJD <= 0 || maxJD > startJD + maxDays) { return nil; }

    return @{
        @"maxJD":           @(maxJD),
        @"firstContactJD":  @(tret[1]),
        @"secondContactJD": @(tret[2]),
        @"thirdContactJD":  @(tret[3]),
        @"fourthContactJD": @(tret[4]),
        @"isTotal":         @((result & SE_ECL_TOTAL)   != 0),
        @"isAnnular":       @((result & (SE_ECL_ANNULAR | SE_ECL_ANNULAR_TOTAL)) != 0),
        @"isPartial":       @((result & SE_ECL_PARTIAL) != 0),
        // attr[0] is the fraction of the solar diameter covered at this place.
        @"magnitude":       @(attr[0]),
        @"isVisible":       @YES
    };
}

- (nullable NSDictionary *)nextLunarEclipseVisibleFromJD:(double)startJD
                                                latitude:(double)lat
                                               longitude:(double)lon
                                             maxDaysAhead:(double)maxDays {
    double geopos[3] = { lon, lat, 0.0 };
    double tret[20]  = {0};
    double attr[20]  = {0};
    char errorMessage[256] = {0};

    int32 result = swe_lun_eclipse_when_loc(startJD, SEFLG_SWIEPH, geopos, tret, attr, 0, errorMessage);
    if (result < 0) { return nil; }

    double maxJD = tret[0];
    if (maxJD <= 0 || maxJD > startJD + maxDays) { return nil; }

    // Lunar tret layout differs from solar: [1] is unused, the phases start at [2].
    return @{
        @"maxJD":             @(maxJD),
        @"partialBeginJD":    @(tret[2]),
        @"partialEndJD":      @(tret[3]),
        @"totalBeginJD":      @(tret[4]),
        @"totalEndJD":        @(tret[5]),
        @"penumbralBeginJD":  @(tret[6]),
        @"penumbralEndJD":    @(tret[7]),
        @"isTotal":           @((result & SE_ECL_TOTAL)     != 0),
        @"isPartial":         @((result & SE_ECL_PARTIAL)   != 0),
        @"isPenumbral":       @((result & SE_ECL_PENUMBRAL) != 0),
        // Two magnitudes, and which one is meaningful depends on the eclipse:
        // attr[0] is umbral, attr[1] penumbral. A penumbral eclipse never enters
        // the umbra, so its attr[0] is legitimately 0 — reporting that as "the"
        // magnitude would make a real eclipse look like a null result.
        @"umbralMagnitude":    @(attr[0]),
        @"penumbralMagnitude": @(attr[1]),
        @"isVisible":          @YES
    };
}

@end
