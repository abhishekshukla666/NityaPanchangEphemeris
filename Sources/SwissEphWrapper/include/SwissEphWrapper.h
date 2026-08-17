//
//  SwissEphWrapper.h
//  NityaPanchangam
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SwissEphWrapper : NSObject

/// Purnimanta tithi number (1–30): Krishna 1–15 (1=Pratipada … 15=Amavasya),
/// then Shukla 16–30 (16=Pratipada … 30=Purnima).
- (int)calculateTithiNumberForJulianDay:(double)jd;
- (NSDictionary *)calculateTithiForDate:(NSDate *)date
                               latitude:(double)latitude
                              longitude:(double)longitude;

- (NSDictionary *)calculateSunriseSunsetForDate:(NSDate *)date
                                       latitude:(double)latitude
                                      longitude:(double)longitude;

/// Solar month (Saura Mana): Sun's current sidereal rashi → 1–12 (Chaitra=1…Phalguna=12).
- (int)calculateLunarMonthForJulianDay:(double)jd;

/// Purnimanta month: Sun's rashi at the NEXT upcoming Purnima → 1–12.
/// The upcoming Purnima always closes the current Purnimanta month, regardless of paksha.
- (int)calculatePurnimantaMonthForJulianDay:(double)jd;

/// Amanta month: Sun's rashi at the Purnima within the current Amanta month → 1–12.
/// For Shukla Paksha this is the upcoming Purnima; for Krishna Paksha it is the last one.
//- (int)calculateAmantaMonthForJulianDay:(double)jd;

/// Amanta Adhik Maas: no Sankranti between the two Amavasyas bracketing the current date.
/// Use this for Amanta and Solar calendar display.
- (BOOL)calculateIsAdhikMaasForJulianDay:(double)jd;

/// Purnimanta Adhik Maas: checks whether the upcoming Purnima (which closes the current
/// Purnimanta month) falls within an Amanta Adhik window.
/// This is the correct criterion for Purnimanta display: the Adhik period ends at the
/// Purnima (not the Amavasya), giving a full-length regular month immediately after.
- (BOOL)calculateIsPurnimantaAdhikMaasForJulianDay:(double)jd;

- (double)getJulianDayUTCFromDate:(NSDate *)date;

- (int)calculateYogaForJulianDay:(double)jd;
- (int)calculateNakshatraForJulianDay:(double)jd;
- (double)calculateNakshatraEndTimeForJulianDay:(double)startJD;

- (NSDictionary *)calculateMuhuratsWithSunrise:(double)sunriseJD sunset:(double)sunsetJD weekday:(int)weekday;
- (double)calculateYogaEndTimeForJulianDay:(double)startJD;
- (int)calculateMoonRashiForJulianDay:(double)jd;

/// Returns an array of 9 NSDictionary objects (one per Navagraha).
/// Each dict has: planetIndex (0–8), longitude (0–360), rashiNumber (1–12), degreesInSign (0–30).
- (NSArray<NSDictionary *> *)calculatePlanetPositionsForJulianDay:(double)jd;

/// Returns the sidereal Ascendant (Lagna) longitude in degrees (0–360) using Lahiri ayanamsha.
- (double)calculateAscendantAtJD:(double)jd latitude:(double)lat longitude:(double)lon;

#pragma mark - Eclipses (Grahan)

/// Next solar eclipse VISIBLE FROM the given place, searching forward from `startJD`.
///
/// Uses swe_sol_eclipse_when_loc, which is the location-aware search: it returns
/// only eclipses actually visible at that latitude/longitude, and reports the
/// local contact times rather than global ones. This is the distinction that
/// matters for observance — Sutak is kept only where the eclipse is visible.
///
/// Returns nil if none is found inside the search window. Otherwise a dict with:
///   maxJD, firstContactJD, secondContactJD, thirdContactJD, fourthContactJD (double)
///   — second/third are 0 when the eclipse is not total/annular at this place.
///   isTotal, isAnnular, isPartial (BOOL)
///   magnitude (double), isVisible (BOOL — always YES for this call)
- (nullable NSDictionary *)nextSolarEclipseVisibleFromJD:(double)startJD
                                                latitude:(double)lat
                                               longitude:(double)lon
                                             maxDaysAhead:(double)maxDays;

/// Next lunar eclipse VISIBLE FROM the given place, searching forward from `startJD`.
///
/// Uses swe_lun_eclipse_when_loc. A lunar eclipse is visible wherever the Moon is
/// above the horizon during it, so this can differ from the solar case in how much
/// of the event is observable locally.
///
/// Returns nil if none is found. Otherwise a dict with:
///   maxJD, partialBeginJD, partialEndJD, totalBeginJD, totalEndJD,
///   penumbralBeginJD, penumbralEndJD (double) — 0 where the phase does not occur
///   isTotal, isPartial, isPenumbral (BOOL)
///   magnitude (double), isVisible (BOOL)
- (nullable NSDictionary *)nextLunarEclipseVisibleFromJD:(double)startJD
                                                latitude:(double)lat
                                               longitude:(double)lon
                                             maxDaysAhead:(double)maxDays;

@end

NS_ASSUME_NONNULL_END
