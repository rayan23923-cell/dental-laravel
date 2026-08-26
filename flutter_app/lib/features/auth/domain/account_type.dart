/// Which login endpoint an account came from.
///
/// `GET /me`'s response has no field telling the client whether it got back
/// a `UserResource` (staff) or `DoctorResource` (doctor) shape. Rather than
/// guessing from the JSON shape, the client remembers which endpoint it
/// logged in through and persists that choice (see `TokenStorage`), so a
/// cold-start session restore knows which parser to use.
enum AccountType { staff, doctor }
