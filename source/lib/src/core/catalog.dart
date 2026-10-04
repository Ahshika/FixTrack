/// الماركات والموديلات الشائعة في مصر، عشان الاستلام يبقى أسرع.
/// المستخدم يقدر يكتب أي ماركة أو موديل مش موجود في القائمة.
const deviceCatalog = <String, List<String>>{
  'Samsung': [
    'Galaxy A05', 'Galaxy A05s', 'Galaxy A06', 'Galaxy A15', 'Galaxy A16', 'Galaxy A25', 'Galaxy A26',
    'Galaxy A35', 'Galaxy A36', 'Galaxy A54', 'Galaxy A55', 'Galaxy A56', 'Galaxy M14', 'Galaxy M34',
    'Galaxy S22', 'Galaxy S23', 'Galaxy S23 Ultra', 'Galaxy S24', 'Galaxy S24 Ultra', 'Galaxy S25',
    'Galaxy S25 Ultra', 'Galaxy Note 20 Ultra', 'Galaxy Z Flip', 'Galaxy Z Fold', 'Galaxy Tab A9',
  ],
  'Apple': [
    'iPhone 11', 'iPhone 11 Pro Max', 'iPhone 12', 'iPhone 12 Pro Max', 'iPhone 13', 'iPhone 13 Pro Max',
    'iPhone 14', 'iPhone 14 Pro', 'iPhone 14 Pro Max', 'iPhone 15', 'iPhone 15 Pro', 'iPhone 15 Pro Max',
    'iPhone 16', 'iPhone 16 Pro', 'iPhone 16 Pro Max', 'iPhone 17', 'iPhone 17 Pro', 'iPhone 17 Pro Max',
    'iPhone X', 'iPhone XR', 'iPhone XS Max', 'iPhone SE',
  ],
  'Xiaomi': [
    'Redmi 13C', 'Redmi 14C', 'Redmi A3', 'Redmi Note 12', 'Redmi Note 13', 'Redmi Note 13 Pro',
    'Redmi Note 14', 'Redmi Note 14 Pro', 'Poco X6 Pro', 'Poco X7', 'Poco F6', 'Poco M6', 'Xiaomi 14',
    'Xiaomi 14T', 'Redmi Pad SE',
  ],
  'Oppo': ['A18', 'A38', 'A58', 'A60', 'A78', 'A79', 'Reno 10', 'Reno 11', 'Reno 12', 'Reno 13', 'Find X'],
  'Realme': ['C51', 'C53', 'C55', 'C61', 'C63', 'C65', 'C67', 'C75', 'Note 50', 'Realme 12', 'Realme 13', 'Realme 14'],
  'Vivo': ['Y03', 'Y17s', 'Y18', 'Y28', 'Y36', 'V29', 'V30', 'V40'],
  'Infinix': ['Hot 40', 'Hot 40i', 'Hot 50', 'Note 30', 'Note 40', 'Note 50', 'Smart 8', 'Smart 9', 'Zero 30'],
  'Tecno': ['Spark 20', 'Spark 20 Pro', 'Spark 30', 'Camon 20', 'Camon 30', 'Pova 6', 'Pop 8'],
  'Honor': ['X5 Plus', 'X6b', 'X7b', 'X8b', 'X9b', 'X9c', 'Magic 6', '200'],
  'Huawei': ['Nova 10', 'Nova 11', 'Nova 12', 'Nova Y70', 'Y9a', 'Y9 Prime', 'P30'],
  'Nokia': ['C32', 'G22', 'G42', '105', '106'],
  'Motorola': ['Moto G14', 'Moto G24', 'Moto G54', 'Edge 50'],
  'OnePlus': ['Nord CE 3', 'Nord CE 4', '12', '13'],
  'Google Pixel': ['Pixel 7', 'Pixel 8', 'Pixel 9'],
  'Lenovo': ['Tab M10', 'Tab M11', 'Tab P11'],
};

const deviceTypes = {
  'phone': 'موبايل',
  'tablet': 'تابلت',
  'watch': 'ساعة',
  'laptop': 'لابتوب',
  'other': 'أخرى',
};
