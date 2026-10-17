<div class="actions">
    @if ($license->machine_id)
        <form class="inline" method="POST" action="{{ route('licensing.codes.update', $license) }}" data-confirm="تحرير الرمز؟ سيتوقف هذا الحاسوب عن استلام التحديثات، ويمكن استخدام الرمز على حاسوب آخر.">
            @csrf @method('PATCH') <input type="hidden" name="action" value="release">
            <button class="btn-small" type="submit">تحرير</button>
        </form>
    @endif
    @if ($license->revoked_at)
        <form class="inline" method="POST" action="{{ route('licensing.codes.update', $license) }}">
            @csrf @method('PATCH') <input type="hidden" name="action" value="restore">
            <button class="btn-small" type="submit">إعادة تشغيل</button>
        </form>
    @else
        <form class="inline" method="POST" action="{{ route('licensing.codes.update', $license) }}" data-confirm="إيقاف الرمز؟ لن يُفعَّل به أي حاسوب ولن يستلم التحديثات.">
            @csrf @method('PATCH') <input type="hidden" name="action" value="revoke">
            <button class="btn-small btn-danger" type="submit">إيقاف</button>
        </form>
    @endif
    @unless ($license->machine_id)
        <form class="inline" method="POST" action="{{ route('licensing.codes.destroy', $license) }}" data-confirm="حذف الرمز؟">
            @csrf @method('DELETE')
            <button class="btn-small btn-danger" type="submit">حذف</button>
        </form>
    @endunless
</div>
