/**
 * The payments page's name for an account's scope (2026-10-26, by request):
 * "مدفوعات المختبر" for the lab's grant, "واردات التذاكر" for the ticket
 * desk's, "المدفوعات" otherwise. [scope] is `PaymentScope::sources()`.
 */
export function paymentsTitleFor(t, scope) {
    if (Array.isArray(scope) && scope.length === 1) {
        return scope[0] === 'lab' ? t('nav.labPayments') : t('nav.ticketPayments');
    }
    return t('nav.payments');
}
