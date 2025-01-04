--@noindex
--NoIndex: true

local tk = {}
local r = reaper

tk.scales = {
    ["Major"] = {0, 2, 4, 5, 7, 9, 11},
    ["Minor"] = {0, 2, 3, 5, 7, 8, 10},
    ["Harmonic Minor"] = {0, 2, 3, 5, 7, 8, 11},
    ["Melodic Minor"] = {0, 2, 3, 5, 7, 9, 11},
    ["Dorian"] = {0, 2, 3, 5, 7, 9, 10},
    ["Phrygian"] = {0, 1, 3, 5, 7, 8, 10},
    ["Lydian"] = {0, 2, 4, 6, 7, 9, 11},
    ["Mixolydian"] = {0, 2, 4, 5, 7, 9, 10},
    ["Locrian"] = {0, 1, 3, 5, 6, 8, 10},
    ["Major Pentatonic"] = {0, 2, 4, 7, 9},
    ["Minor Pentatonic"] = {0, 3, 5, 7, 10},
    ["Blues"] = {0, 3, 5, 6, 7, 10},
    ["Major Bebop"] = {0, 2, 4, 5, 7, 8, 9, 11},
    ["Minor Bebop"] = {0, 2, 3, 4, 5, 7, 9, 10},
    ["Whole Tone"] = {0, 2, 4, 6, 8, 10},
    ["Diminished"] = {0, 2, 3, 5, 6, 8, 9, 11},
    ["Augmented"] = {0, 3, 4, 7, 8, 11},
    ["Chromatic"] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11},
    ["Major Bulgarian"] = {0, 2, 3, 6, 7, 9, 10},
    ["Major Hexatonic"] = {0, 2, 4, 7, 9, 11},
    ["Major Persian"] = {0, 1, 4, 5, 6, 8, 11},
    ["Major Polymode"] = {0, 2, 3, 4, 5, 7, 9, 11},
    ["Minor Hungarian"] = {0, 2, 3, 6, 7, 8, 11},
    ["Minor Neapolitan"] = {0, 1, 3, 5, 7, 8, 11},
    ["Minor Polymode"] = {0, 2, 3, 5, 7, 8, 10, 11},
    ["Minor Romanian"] = {0, 2, 3, 6, 7, 9, 10},
    ["Arabic"] = {0, 1, 4, 5, 7, 8, 11},
    ["Bebop Dominant"] = {0, 2, 4, 5, 7, 9, 10, 11},
    ["Blues Nonatonic"] = {0, 2, 3, 4, 5, 6, 7, 9, 10},
    ["Eastern"] = {0, 1, 4, 5, 7, 8, 10},
    ["Egyptian"] = {0, 2, 5, 7, 10},
    ["Enigmatic"] = {0, 1, 4, 6, 8, 10, 11},
    ["Hirajoshi"] = {0, 2, 3, 7, 8},
    ["Iwato"] = {0, 1, 5, 6, 10},
    ["Japanese Insen"] = {0, 1, 5, 7, 10},
    ["Locrian Super"] = {0, 1, 3, 4, 6, 8, 10},
    ["Neapolitan"] = {0, 1, 3, 5, 7, 9, 11},
    ["Phrygian Dominant"] = {0, 1, 4, 5, 7, 8, 10},
    ["Piongio"] = {0, 2, 4, 7, 9},
    ["Prometheus"] = {0, 2, 4, 6, 9, 10}
  }
  
tk.keys = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
  
tk.ordered_scales = {
    "Major", "Minor", "Harmonic Minor", "Melodic Minor", "Dorian", "Phrygian", "Lydian", "Mixolydian", "Locrian",
    "Major Pentatonic", "Minor Pentatonic", "Blues", "Major Bebop", "Minor Bebop", "Whole Tone", "Diminished",
    "Augmented", "Chromatic", "Major Bulgarian", "Major Hexatonic", "Major Persian", "Major Polymode",
    "Minor Hungarian", "Minor Neapolitan", "Minor Polymode", "Minor Romanian", "Arabic", "Bebop Dominant",
    "Blues Nonatonic", "Eastern", "Egyptian", "Enigmatic", "Hirajoshi", "Iwato", "Japanese Insen", "Locrian Super",
    "Neapolitan", "Phrygian Dominant", "Piongio", "Prometheus"
  }

function tk.getScalePattern(key, scaleName)
    if not tk.scales[scaleName] then
        return nil, "Тональность не найдена"
    end

    -- Находим индекс ключа (0-11)
    local keyIndex = -1
    for i, k in ipairs(tk.keys) do
        if k == key then
            keyIndex = i - 1
            break
        end
    end

    if keyIndex == -1 then
        return nil, "Ключ не найден"
    end

    -- Создаем пустой паттерн из 12 нот
    local pattern = {}
    for i = 1, 12 do
        pattern[i] = 0
    end

    -- Заполняем паттерн на основе интервалов гаммы
    for _, interval in ipairs(tk.scales[scaleName]) do
        local index = (interval + keyIndex) % 12 + 1
        pattern[index] = 1
    end

    return pattern
end



return tk
