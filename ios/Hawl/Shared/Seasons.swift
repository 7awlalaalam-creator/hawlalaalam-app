import Foundation

// رمضان، فضائل الصلوات، الصيام المسنون، والبطاقة الذكية — نقل لـ Ramadan.java و Fadl.java و Smart.java

// MARK: - رمضان

enum Ramadan {
    static func active(_ now: Date = Date()) -> Bool { Hijri.parts(now).month == 9 }

    /** اليوم من رمضان (١..٣٠) أو ٠ */
    static func day(_ now: Date = Date()) -> Int {
        let h = Hijri.parts(now)
        return h.month == 9 ? h.day : 0
    }

    /** أيام حتى بداية رمضان القادم (٠ إن كان قائمًا، -١ إن تعذّر) */
    static func daysUntil(_ now: Date = Date()) -> Int {
        if active(now) { return 0 }
        let cal = Calendar.current
        for i in 1..<400 {
            guard let d = cal.date(byAdding: .day, value: i, to: now) else { return -1 }
            if Hijri.parts(d).month == 9 { return i }
        }
        return -1
    }

    /** الأيام المتبقية من رمضان بما فيها اليوم */
    static func daysLeftInRamadan(_ now: Date = Date()) -> Int {
        if !active(now) { return 0 }
        let cal = Calendar.current
        var n = 0
        var d = now
        while n < 31 && Hijri.parts(d).month == 9 {
            n += 1
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return max(1, n)
    }

    /** الإمساك: قبل الفجر بعشر دقائق */
    static func imsak(_ day: Date) -> Date { Prayer.times(for: day)[Prayer.fajr].addingTimeInterval(-600) }

    static func iftar(_ day: Date) -> Date { Prayer.times(for: day)[Prayer.maghrib] }

    /** الحدث القادم: (true للإفطار / false للإمساك، الوقت) */
    static func nextEvent(_ now: Date = Date()) -> (iftar: Bool, at: Date) {
        let im = imsak(now), ift = iftar(now)
        if now < im { return (false, im) }
        if now < ift { return (true, ift) }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        return (false, imsak(tomorrow))
    }

    static func tadabburURL(_ now: Date = Date()) -> URL {
        let d = day(now)
        return d > 0 ? Links.site("ramadan-day-\(d).html") : Links.site("ramadan-tadabbur-ar.html")
    }

    static func ordinal(_ d: Int) -> String {
        let o = ["", L("الأول"), L("الثاني"), L("الثالث"), L("الرابع"), L("الخامس"), L("السادس"), L("السابع"), L("الثامن"), L("التاسع"), L("العاشر")]
        if d >= 1 && d <= 10 { return L("اليوم ") + o[d] }
        return L("اليوم ") + ar(d)
    }
}

// MARK: - فضائل الصلوات والصيام المسنون

enum Fadl {
    private static let fajrList: [(String, String)] = [
        (L("«مَنْ صَلَّى الصُّبْحَ فَهُوَ فِي ذِمَّةِ اللَّهِ»"), L("رواه مسلم")),
        (L("«رَكْعَتَا الْفَجْرِ خَيْرٌ مِنَ الدُّنْيَا وَمَا فِيهَا»"), L("رواه مسلم")),
        (L("«وَمَنْ صَلَّى الصُّبْحَ فِي جَمَاعَةٍ فَكَأَنَّمَا صَلَّى اللَّيْلَ كُلَّهُ»"), L("رواه مسلم")),
        (L("«مَنْ صَلَّى الْبَرْدَيْنِ دَخَلَ الْجَنَّةَ» والبردان: الفجر والعصر"), L("متفق عليه")),
        (L("﴿وَقُرْآنَ الْفَجْرِ ۖ إِنَّ قُرْآنَ الْفَجْرِ كَانَ مَشْهُودًا﴾"), L("سورة الإسراء: ٧٨")),
    ]

    private static let sunriseList: [(String, String)] = [
        (L("«مَنْ صَلَّى الْغَدَاةَ فِي جَمَاعَةٍ ثُمَّ قَعَدَ يَذْكُرُ اللَّهَ حَتَّى تَطْلُعَ الشَّمْسُ، ثُمَّ صَلَّى رَكْعَتَيْنِ، كَانَتْ لَهُ كَأَجْرِ حَجَّةٍ وَعُمْرَةٍ تَامَّةٍ تَامَّةٍ تَامَّةٍ»"),
         L("رواه الترمذي وحسّنه الألباني")),
        (L("«يُصْبِحُ عَلَى كُلِّ سُلَامَى مِنْ أَحَدِكُمْ صَدَقَةٌ… وَيُجْزِئُ مِنْ ذَلِكَ رَكْعَتَانِ يَرْكَعُهُمَا مِنَ الضُّحَى»"),
         L("رواه مسلم")),
        (L("«صَلَاةُ الْأَوَّابِينَ حِينَ تَرْمَضُ الْفِصَالُ» أي أفضل وقت الضحى حين يشتد الحر"), L("رواه مسلم")),
    ]

    private static let dhuhrList: [(String, String)] = [
        (L("«إِنَّهَا سَاعَةٌ تُفْتَحُ فِيهَا أَبْوَابُ السَّمَاءِ، وَأُحِبُّ أَنْ يَصْعَدَ لِي فِيهَا عَمَلٌ صَالِحٌ»"),
         L("رواه الترمذي وصححه الألباني")),
        (L("«مَنْ حَافَظَ عَلَى أَرْبَعِ رَكَعَاتٍ قَبْلَ الظُّهْرِ وَأَرْبَعٍ بَعْدَهَا حَرَّمَهُ اللَّهُ عَلَى النَّارِ»"),
         L("رواه أبو داود والترمذي وصححه الألباني")),
        (L("سُئل النبي ﷺ: أيُّ العمل أحبُّ إلى الله؟ قال: «الصَّلَاةُ عَلَى وَقْتِهَا»"), L("متفق عليه")),
        (L("«مَنْ تَطَهَّرَ فِي بَيْتِهِ ثُمَّ مَشَى إِلَى بَيْتٍ مِنْ بُيُوتِ اللَّهِ لِيَقْضِيَ فَرِيضَةً مِنْ فَرَائِضِ اللَّهِ، كَانَتْ خَطْوَتَاهُ إِحْدَاهُمَا تَحُطُّ خَطِيئَةً، وَالْأُخْرَى تَرْفَعُ دَرَجَةً»"),
         L("رواه مسلم")),
    ]

    private static let jumuahList: [(String, String)] = [
        (L("«خَيْرُ يَوْمٍ طَلَعَتْ عَلَيْهِ الشَّمْسُ يَوْمُ الْجُمُعَةِ»"), L("رواه مسلم")),
        (L("«مَنْ تَوَضَّأَ فَأَحْسَنَ الْوُضُوءَ، ثُمَّ أَتَى الْجُمُعَةَ فَاسْتَمَعَ وَأَنْصَتَ، غُفِرَ لَهُ مَا بَيْنَهُ وَبَيْنَ الْجُمُعَةِ، وَزِيَادَةُ ثَلَاثَةِ أَيَّامٍ»"),
         L("رواه مسلم")),
        (L("«إِنَّ مِنْ أَفْضَلِ أَيَّامِكُمْ يَوْمَ الْجُمُعَةِ… فَأَكْثِرُوا عَلَيَّ مِنَ الصَّلَاةِ فِيهِ»"),
         L("رواه أبو داود وصححه الألباني")),
    ]

    private static let asrList: [(String, String)] = [
        (L("﴿حَافِظُوا عَلَى الصَّلَوَاتِ وَالصَّلَاةِ الْوُسْطَىٰ﴾ والوسطى هي العصر كما في الصحيحين"), L("سورة البقرة: ٢٣٨")),
        (L("«لَنْ يَلِجَ النَّارَ أَحَدٌ صَلَّى قَبْلَ طُلُوعِ الشَّمْسِ وَقَبْلَ غُرُوبِهَا» يعني الفجر والعصر"), L("رواه مسلم")),
        (L("«يَتَعَاقَبُونَ فِيكُمْ مَلَائِكَةٌ بِاللَّيْلِ وَمَلَائِكَةٌ بِالنَّهَارِ، وَيَجْتَمِعُونَ فِي صَلَاةِ الْفَجْرِ وَصَلَاةِ الْعَصْرِ»"),
         L("متفق عليه")),
        (L("«مَنْ صَلَّى الْبَرْدَيْنِ دَخَلَ الْجَنَّةَ» والبردان: الفجر والعصر"), L("متفق عليه")),
    ]

    /** عصر الجمعة: ساعة الإجابة */
    private static let asrFriday = (L("ساعة الإجابة يوم الجمعة: «فَالْتَمِسُوهَا آخِرَ سَاعَةٍ بَعْدَ الْعَصْرِ»"), L("رواه أبو داود وصححه الألباني"))

    private static let maghribList: [(String, String)] = [
        (L("«لَا تَزَالُ أُمَّتِي بِخَيْرٍ مَا لَمْ يُؤَخِّرُوا الْمَغْرِبَ إِلَى أَنْ تَشْتَبِكَ النُّجُومُ»"),
         L("رواه أبو داود وصححه الألباني")),
        (L("«صَلُّوا قَبْلَ صَلَاةِ الْمَغْرِبِ» قال في الثالثة: «لِمَنْ شَاءَ»"), L("رواه البخاري")),
        (L("«مَنْ صَلَّى اثْنَتَيْ عَشْرَةَ رَكْعَةً فِي يَوْمٍ وَلَيْلَةٍ بُنِيَ لَهُ بِهِنَّ بَيْتٌ فِي الْجَنَّةِ»"), L("رواه مسلم")),
    ]

    private static let ishaList: [(String, String)] = [
        (L("«مَنْ صَلَّى الْعِشَاءَ فِي جَمَاعَةٍ فَكَأَنَّمَا قَامَ نِصْفَ اللَّيْلِ»"), L("رواه مسلم")),
        (L("«وَلَوْ يَعْلَمُونَ مَا فِي الْعَتَمَةِ وَالصُّبْحِ لَأَتَوْهُمَا وَلَوْ حَبْوًا»"), L("متفق عليه")),
        (L("«اجْعَلُوا آخِرَ صَلَاتِكُمْ بِاللَّيْلِ وِتْرًا»"), L("متفق عليه")),
        (L("«إِنَّ اللَّهَ وِتْرٌ يُحِبُّ الْوِتْرَ»"), L("متفق عليه")),
    ]

    private static func rotate(_ list: [(String, String)], _ day: Date) -> (String, String) {
        let doy = Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: day) ?? 1
        return list[doy % list.count]
    }

    /** فضل الصلاة (أو الشروق) لهذا اليوم: (المتن، المصدر) */
    static func of(_ index: Int, on day: Date) -> (String, String) {
        let friday = Calendar.current.component(.weekday, from: day) == 6
        switch index {
        case Prayer.fajr: return rotate(fajrList, day)
        case Prayer.sunrise: return rotate(sunriseList, day)
        case Prayer.dhuhr: return friday ? rotate(jumuahList, day) : rotate(dhuhrList, day)
        case Prayer.asr: return friday ? asrFriday : rotate(asrList, day)
        case Prayer.maghrib: return rotate(maghribList, day)
        default: return rotate(ishaList, day)
        }
    }

    struct Fast { let title: String, text: String, source: String }

    /** هل اليوم المعطى يوم صيام مسنون؟ (حسب تقويم أم القرى) */
    static func fastDay(_ day: Date) -> Fast? {
        let h = Hijri.parts(day)
        let m = h.month, d = h.day
        if m <= 0 { return nil }
        // لا صيام تطوع في رمضان، ويحرم صيام العيدين وأيام التشريق
        if m == 9 { return nil }
        if m == 10 && d == 1 { return nil }
        if m == 12 && d >= 10 && d <= 13 { return nil }
        if m == 12 && d == 9 {
            return Fast(title: L("صيام يوم عرفة"),
                        text: L("«صِيَامُ يَوْمِ عَرَفَةَ أَحْتَسِبُ عَلَى اللَّهِ أَنْ يُكَفِّرَ السَّنَةَ الَّتِي قَبْلَهُ وَالسَّنَةَ الَّتِي بَعْدَهُ»"),
                        source: L("رواه مسلم"))
        }
        if m == 1 && (d == 9 || d == 10) {
            return Fast(title: d == 10 ? L("صيام يوم عاشوراء") : L("صيام تاسوعاء"),
                        text: L("«صِيَامُ يَوْمِ عَاشُورَاءَ أَحْتَسِبُ عَلَى اللَّهِ أَنْ يُكَفِّرَ السَّنَةَ الَّتِي قَبْلَهُ»"),
                        source: L("رواه مسلم"))
        }
        if d >= 13 && d <= 15 {
            return Fast(title: L("صيام الأيام البيض"),
                        text: L("«صِيَامُ ثَلَاثَةِ أَيَّامٍ مِنْ كُلِّ شَهْرٍ صِيَامُ الدَّهْرِ كُلِّهِ»"), source: L("متفق عليه"))
        }
        let dow = Calendar.current.component(.weekday, from: day)
        if dow == 2 || dow == 5 {
            return Fast(title: dow == 2 ? L("صيام الاثنين") : L("صيام الخميس"),
                        text: L("«تُعْرَضُ الْأَعْمَالُ يَوْمَ الِاثْنَيْنِ وَالْخَمِيسِ، فَأُحِبُّ أَنْ يُعْرَضَ عَمَلِي وَأَنَا صَائِمٌ»"),
                        source: L("رواه الترمذي وصححه الألباني"))
        }
        return nil
    }

    /** صيام اليوم التالي ليوم معيّن إن كان مسنونًا */
    static func fastAfter(_ day: Date) -> Fast? {
        let cal = Calendar.current
        guard let t = cal.date(byAdding: .day, value: 1, to: day),
              let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: t) else { return nil }
        return fastDay(noon)
    }
}

// MARK: - البطاقة الذكية (ويدجت المواقيت)

/**
 * سطر يتغيّر حسب الوقت واليوم والمناسبة.
 * الأولوية: رمضان ← ساعة الإجابة ← الجمعة ← أوقات اليوم (الشروق، الضحى، المساء، الثلث الأخير، الوتر).
 */
enum Smart {
    struct Tip { let text: String; let url: URL; let until: Date }

    static func tip(_ now: Date = Date()) -> Tip {
        let cal = Calendar.current
        let t = Prayer.times(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        let fajr = t[Prayer.fajr], sunrise = t[Prayer.sunrise], dhuhr = t[Prayer.dhuhr]
        let asr = t[Prayer.asr], maghrib = t[Prayer.maghrib], isha = t[Prayer.isha]
        let duha = sunrise.addingTimeInterval(15 * 60)
        let midnight = cal.startOfDay(for: tomorrow).addingTimeInterval(5)

        // الليل الحالي: من مغرب أمس إلى فجر اليوم، أو من مغرب اليوم إلى فجر الغد
        let nightStart: Date, nightEnd: Date
        if now < fajr { nightStart = Prayer.times(for: yesterday)[Prayer.maghrib]; nightEnd = fajr }
        else { nightStart = maghrib; nightEnd = Prayer.times(for: tomorrow)[Prayer.fajr] }
        let lastThird = nightEnd.addingTimeInterval(-nightEnd.timeIntervalSince(nightStart) / 3)
        let friday = cal.component(.weekday, from: now) == 6
        let home = Links.home
        let mushaf = Links.mushaf()

        // ١) رمضان: الإفطار والسحور
        if Ramadan.active(now) {
            if now >= fajr && now < maghrib {
                return Tip(text: L("🌙 الإفطار ") + formatTime(maghrib) + L(" · «لِلصَّائِمِ فَرْحَتَانِ»"), url: Ramadan.tadabburURL(now), until: maghrib)
            }
            if now >= lastThird && now < fajr {
                return Tip(text: L("🍽 وقت السحور · الإمساك قبل الفجر ") + formatTime(fajr) + L(" · «تسحّروا فإن في السحور بركة»"), url: home, until: fajr)
            }
        }

        // ٢) يوم الجمعة
        if friday && now >= asr && now < maghrib {
            let lastHour = maghrib.addingTimeInterval(-3600)
            let txt = now >= lastHour
                ? L("🤲 آخر ساعة من الجمعة الآن · ساعة إجابة، أكثِر من الدعاء")
                : L("🤲 ساعة الإجابة آخر ساعة بعد العصر · من ") + formatTime(lastHour)
            return Tip(text: txt, url: home, until: now >= lastHour ? maghrib : lastHour)
        }
        if friday && now >= fajr && now < asr {
            return Tip(text: L("📖 يوم الجمعة: سورة الكهف · وأكثِروا من الصلاة على النبي ﷺ"), url: Links.kahf, until: asr)
        }

        // ٣) أوقات اليوم
        if now >= fajr && now < sunrise {
            return Tip(text: L("🌅 الشروق ") + formatTime(sunrise) + L(" · اجلس تذكر الله حتى تطلع الشمس"), url: Links.azkar, until: sunrise)
        }
        if now >= sunrise && now < duha {
            return Tip(text: L("⏳ وقت نهي حتى ترتفع الشمس · يبدأ الضحى ") + formatTime(duha), url: Links.azkar, until: duha)
        }
        let dhuhrSoon = dhuhr.addingTimeInterval(-600)
        if now >= duha && now < dhuhrSoon {
            return Tip(text: L("☀️ وقت الضحى الآن · ركعتان تجزئان عن صدقة ٣٦٠ مفصلًا"), url: home, until: dhuhrSoon)
        }
        if now >= asr && now < maghrib {
            return Tip(text: L("🌇 أذكار المساء · المغرب ") + formatTime(maghrib), url: Links.azkar, until: maghrib)
        }
        if now >= maghrib && now < isha {
            if let fast = Fadl.fastAfter(now) {
                return Tip(text: L("🌙 غدًا ") + fast.title + L(" · تذكّر النية والسحور"), url: home, until: isha)
            }
            return Tip(text: L("📖 بين المغرب والعشاء · وقت طيّب لوردك اليومي"), url: mushaf, until: isha)
        }
        if now >= lastThird && now < fajr {
            return Tip(text: L("🌌 الثلث الأخير من الليل · «ينزل ربنا إلى السماء الدنيا… من يدعوني فأستجيب له»"), url: home, until: fajr)
        }
        if now >= isha || now < fajr {
            let fast = now >= isha ? Fadl.fastAfter(now) : Fadl.fastDay(now)
            let until = min(lastThird, now >= isha ? midnight : lastThird)
            if let f = fast {
                return Tip(text: "🌙 " + (now >= isha ? L("غدًا ") : L("اليوم ")) + f.title + L(" · تذكّر النية والسحور"), url: home, until: until)
            }
            return Tip(text: L("🌙 الوتر قبل النوم · «اجعلوا آخر صلاتكم بالليل وترًا»"), url: home, until: until)
        }

        // ٤) بقية النهار: الورد
        if Khatma.running {
            let left = Khatma.todayRemaining
            if left > 0 {
                return Tip(text: L("📖 بقي ") + ar(left) + L(" صفحات من وردك · اضغط للمتابعة"), url: Links.page(Khatma.nextPage), until: asr)
            }
            if !Khatma.readingToday { return Tip(text: L("🌿 يوم راحة من وردك · اقرأ إن شئت"), url: mushaf, until: asr) }
            return Tip(text: L("✅ أتممت ورد اليوم · بارك الله فيك"), url: mushaf, until: asr)
        }
        if let f = Fadl.fastDay(now), now < maghrib {
            return Tip(text: L("🌙 اليوم ") + f.title + L(" · الإفطار ") + formatTime(maghrib), url: home, until: maghrib)
        }
        return Tip(text: L("📖 «أحب الأعمال إلى الله أدومها وإن قلّ» · افتح وردك"), url: mushaf, until: asr)
    }
}
