<?php

namespace App\Support;

/**
 * The selectable UI themes.
 *
 * Each theme is a set of CSS custom properties written onto <html> by the
 * root Blade view, so the palette is applied before the first paint — a
 * theme resolved in JavaScript would flash the wrong colours on every load.
 * Tailwind maps semantic utilities (`bg-surface`, `text-accent`, …) onto the
 * same variables in tailwind.config.js, so a theme change needs no rebuild.
 *
 * Colours are stored as space-separated RGB channels, not hex, because
 * Tailwind composes them with `<alpha-value>` (`bg-accent/20` and friends).
 *
 * `unit-dark` is the default and the reference: it is sampled from the
 * dental-unit control panel the login and navigation redesign is modelled
 * on — near-black slate, raised charcoal cards, and a mint accent used only
 * for the active element.
 */
class ThemePalette
{
    public const DEFAULT = 'unit-dark';

    public const THEMES = [
        'unit-dark' => [
            'label' => 'Unit Dark — لوحة الجهاز',
            'description' => 'داكن مع لمسة نعناعية، مطابق لشاشة وحدة الأسنان.',
            'swatch' => ['#101720', '#34e0c0'],
            'dark' => true,
            'tokens' => [
                'bg' => '13 19 26',
                'bg-soft' => '18 25 33',
                'surface' => '28 36 45',
                'surface-2' => '36 46 57',
                'border' => '48 60 73',
                'text' => '240 246 252',
                'muted' => '148 163 179',
                'accent' => '52 224 192',
                'accent-2' => '26 183 168',
                'accent-fg' => '6 32 30',
                'ring' => '52 224 192',
            ],
        ],
        'unit-blue' => [
            'label' => 'Unit Blue — أزرق طبي',
            'description' => 'نفس البنية الداكنة بلمسة أزرق سماوي.',
            'swatch' => ['#0f1620', '#38bdf8'],
            'dark' => true,
            'tokens' => [
                'bg' => '12 18 27',
                'bg-soft' => '17 24 34',
                'surface' => '26 35 47',
                'surface-2' => '34 45 60',
                'border' => '45 59 76',
                'text' => '240 246 252',
                'muted' => '146 161 180',
                'accent' => '56 189 248',
                'accent-2' => '14 148 216',
                'accent-fg' => '4 27 40',
                'ring' => '56 189 248',
            ],
        ],
        'unit-violet' => [
            'label' => 'Unit Violet — بنفسجي',
            'description' => 'داكن أنيق بلمسة بنفسجية.',
            'swatch' => ['#141225', '#a78bfa'],
            'dark' => true,
            'tokens' => [
                'bg' => '16 15 30',
                'bg-soft' => '22 21 38',
                'surface' => '32 30 52',
                'surface-2' => '42 39 66',
                'border' => '56 52 84',
                'text' => '241 240 252',
                'muted' => '158 154 184',
                'accent' => '167 139 250',
                'accent-2' => '124 92 240',
                'accent-fg' => '24 16 48',
                'ring' => '167 139 250',
            ],
        ],
        'clinic-light' => [
            'label' => 'Clinic Light — فاتح',
            'description' => 'خلفية فاتحة بنفس اللمسة النعناعية.',
            'swatch' => ['#f2f6f9', '#0d9488'],
            'dark' => false,
            'tokens' => [
                'bg' => '241 245 249',
                'bg-soft' => '248 250 252',
                'surface' => '255 255 255',
                'surface-2' => '241 245 249',
                'border' => '212 222 232',
                'text' => '15 30 43',
                'muted' => '95 113 132',
                'accent' => '13 148 136',
                'accent-2' => '15 118 110',
                'accent-fg' => '255 255 255',
                'ring' => '13 148 136',
            ],
        ],
    ];

    public static function resolve(?string $theme): string
    {
        return isset(self::THEMES[$theme]) ? $theme : self::DEFAULT;
    }

    /** The `--c-*` declarations for the <html> style attribute. */
    public static function cssVariables(?string $theme): string
    {
        $tokens = self::THEMES[self::resolve($theme)]['tokens'];

        return collect($tokens)
            ->map(fn ($value, $name) => "--c-{$name}:{$value}")
            ->implode(';');
    }

    public static function isDark(?string $theme): bool
    {
        return self::THEMES[self::resolve($theme)]['dark'];
    }

    /** Shape the settings page renders its theme picker from. */
    public static function forUi(): array
    {
        return collect(self::THEMES)
            ->map(fn ($theme, $key) => [
                'value' => $key,
                'label' => $theme['label'],
                'description' => $theme['description'],
                'swatch' => $theme['swatch'],
                'dark' => $theme['dark'],
            ])
            ->values()
            ->all();
    }
}
