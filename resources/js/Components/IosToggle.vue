<script setup>
/**
 * iOS-style toggle switch — exact dimensions/colours copied from the
 * original's `.ios-toggle` CSS (operative.php): 51×31px track, 27×27px
 * white knob, #ccc off / #34c759 (real iOS green) on, 20px knob travel,
 * .4s transition. Used to show/hide the Endodontics section.
 */
defineProps({
    modelValue: Boolean,
    disabled: Boolean,
});

defineEmits(['update:modelValue']);
</script>

<template>
    <label class="relative inline-block h-[31px] w-[51px]" :class="disabled ? 'opacity-60' : 'cursor-pointer'">
        <input
            type="checkbox"
            :checked="modelValue"
            :disabled="disabled"
            class="peer absolute h-0 w-0 opacity-0"
            @change="$emit('update:modelValue', $event.target.checked)"
        />
        <span
            class="absolute inset-0 rounded-full bg-[#ccc] transition-colors duration-300 peer-checked:bg-[#34c759] peer-focus-visible:ring-2 peer-focus-visible:ring-[#34c759] peer-focus-visible:ring-offset-1"
        ></span>
        <span
            class="pointer-events-none absolute bottom-[2px] left-[2px] h-[27px] w-[27px] rounded-full bg-white shadow transition-transform duration-300 peer-checked:translate-x-[20px]"
        ></span>
    </label>
</template>
