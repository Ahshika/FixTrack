/// مشروع Firebase بتاع FixTrack (واحد لكل المحلات). المفتاح ده عام ومعمول يتحط في التطبيقات؛
/// الحماية الحقيقية في قواعد Firestore (firebase/firestore.rules).
const firebaseProjectId = 'fixtrack-7fcf9';
const firebaseApiKey = 'AIzaSyAfTHWsrWDC0IUNrBFHsOc72tlpcqw1QzE';
const trackingSiteUrl = 'https://fixtrack-7fcf9.web.app';

/// مواعيد الاستلام الافتراضية لو المحل ما حددش: كل الأيام ما عدا الجمعة، من 12 الضهر لـ 10 بالليل.
const defaultPickupHours = {
  'days': [0, 1, 2, 3, 4, 6], // 0 = الأحد ... 6 = السبت (5 = الجمعة)
  'from': '12:00',
  'to': '22:00',
  'slotMinutes': 30,
};
