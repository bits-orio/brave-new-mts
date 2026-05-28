-- scripts/blueprints.lua
-- Maps a team surface to the starter-base blueprint string used to seed it.
--
-- The SAME blueprint works for every planet except Aquilo, which needs extra
-- solar panels (per design). `default` is used for any surface without a
-- specific entry. Paste real exported blueprint strings here in Phase 3.
--
-- The blueprint should contain the power build (solar / accumulators /
-- substations) and a roboport. Logistic chests and their starting items are
-- placed by starter_base.lua, NOT the blueprint, so they can be kept in sync
-- with the anti-soft-lock item list in code.

local M = {}

-- Known planet name fragments we test surface names against (lower-case).
local PLANETS = { "nauvis", "vulcanus", "fulgora", "gleba", "aquilo" }

-- planet key -> exported blueprint string. Empty string == not configured yet.
M.blueprints = {
    -- Walled starter base: bnm-roboport (centre), 47 solar + 16 accumulator
    -- + 2 substation + 2 medium pole + 7 lamp (the protected power core), a
    -- stone-wall perimeter, a logistic chest set (passive/active provider,
    -- requester, buffer, storage), inserters + loaders, and a tiled floor.
    default = "0eNqt3d1uG0cahOF74bG04PxWlW8lMAJZZhICEqWlqGSzge99JdsJnSxb3Q2/Z5YgFUfkx+rhTD/wH5sPd8+7x+P+cNq8+2Ozv304PG3e/fDH5mn/8+Hm7vV7h5v73ebd5unh7uZ4/Xhz2N1tPl1t9oePu/9s3g2f3l9tdofT/rTfffnFz1/8/uPh+f7D7vjyA1d/BZweDrvr327u7jZXm8eHp5dfeTi8PsBLzDr8a7na/L55p5d/fPp09X8xY1vMWImZ2mKmSszcFjNXYpa2mKUSs7bFrJUYtcWoEuO2GFdi0haTSsywbcrRtpbTNseqzfHQNsiqDfLQNsmqTfLQNsqqjfLQNsuqzfLQNsyqDfPQNs2qTfPQNs6qjfPQNs+qzfPYNs+uzfPYNs+u9nLbPLs2z2PbPLs2z2PbPLs2z2PbPLs2z2PbPLs2z2PbPLs2z2PbPLs2z2PbPLs2z1PbPKc2z1PbPKc2z1PbPKd6otE2z6nN89Q2z6nN89Q2z6nN89Q2z6nN89Q2z6nN89Q2z6nN85TO89SpcGa47cwZCznfzPM3J95vnKqWDmhsDFprQVNjUGpBc1vQ+RyoFLQ0Bi21oLUxyLUgtQW5OkZuDJprQWkMUiVo2bYFnZu6FNQ42alN9tI42alN9jJ1dkgpZ+7MKbz3l6WzQ5ZCztqZMxdyzlP94fmnn3bH69tfdk+nt85eX4/oanPc/fv55Qd//Gl/d9odn15/6ml3+/oLXy4VnK8hXHzY83vga9Abj2z0kf+2GBxvft6VHtcD+bjrtvlxt+jjDp2DWxi4dezMKQzcOnUOrgo5c2fOWsg5vyFvbm+f75/vbl5enkuL8deYiyGNi8z5ck/paBoXmfMlllJQ4yKj6vOTtudH8xvPjxoXmPNH/8LR6DzN+8PT7vjyhnirMEopY3fprcBbUVN/9SCPO/dXD/K4jedw5w/+pddrbZtBr2/NYOv5W3V6Gt9aqb211Hj+dv4AWAjytu35id54fty7UBSK2b0LRemP6l0oUsjpXShcyDlP8/3u4/75/np39/JeOO5vrx8f7nZv3bAoHdk3q8b9y0Fd393cP771MbCUo74lzBdD3LuElY4mvUtYISjnqX68eXra/7q7fjw+/Lr/+EZf117EDE1P+fmWQSln/OYpPzUd2liLnPr/3NqEZe5bvC9ORpbexbt0NOd5/3C4vz4+fHh4fDheXIa+5nz3EhT1LkGlY3fvC37+1F16wdP9gp8zU7oltu1bKn05Zeg/NFf+3GE7Nr33zpeVi0FT7wJcfLbm3hW4mLQ0/XFZq0Fr5zKT+kyo7/SgMBO9V2OLh5POoNIcDJ3XY128/9u5keH1NPly0Ni1Enu4nPLNfD9/eDrdfP7NC4vd14O5HDK3rXRj9W9autaQ0uGsDR/c/LdX6mrzcX/8UvUv37kYqq6yKx2a23pJ1WcqTa/b6wlS+WjGvnP5wgiNnSfzxbfG2Hk2X3xyxs7TeU+loM7zeY+loL4rP54up/Re+ikfT++1n3JS78WfctJ5pO8ebj7u3njfT/98y758//T74+uvPjyfHp9Pm4tbXbZ97TJe3jAzdJ6iFv/gqfHGw19XhspJU1utVAf+m9vE1Wvl/tsr+r1nz8PUewWn/Gys1UH6s6X/b5BeV9WGSepcDAqT5M6rROW/OJ1nqcWkedt5llpOGvoWl8uVN/euCaXJnjtvzpX/rt41YSkFdd6e81wKWjvv8ZcPSZ03+ctJ7rzLX05K523+YlLrree/7vOXk4bOG/3lpLHzTn85aeq81V9Omjvv9ZeTls6b/eWktfNufzlJnbf7y0mdn1LLQZ2fUotNsPZ+SlUpqPdT6loK6txwXz6izi335aDOTffloM5t9+Wgzo335aDOrffloM7N9+Wgzu33xSB17r8vB3VuwC8Hde7ALwd1bsEvB3XuwS8HdW7CLwetfbvny0Hq285fDnLf/vlyUPo29BeDvO3bQV8OGvq29JeDOvfil4M6N+OXgzp345eDOrfjl4M69+OXgzo35JeDOnfkl4M6t+QXg9K5J78c1LkpvxzUuSu/HNS5Lb8c1LkvvxzUuTG/HNS5M78c1Lk1vxzUe55dDOo9z/58Vvv+avPb/vhZpf7w0h/L1etNk+X91Q+v989ev8qXr16/+/Wrl1857e++QtZ/nut8veG8/fTNpbaf9ofdx+tfbv57c/x4fftwuD3uTrvr4/7nX75cgCpkDEDGCGRMQMYMZCxAxgpkCMgwkJHvzzAwpwbm1MCcGphTA3NqYE4NzKmBOfV3zekAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEAdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEIdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEEdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOEMdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOECdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdOEKdKGALhTQhQK6UEAXCuhCAV0ooAsFdKGALhTQhQK6UEAXCuhCAV0ooAsFdKGALhTQhQK60EAXGuhCA11ooAsNdKGBLjTQhQa60EAXGuhCA11ooAsNdKGBLjTQhQb6I0B/BOiPAP0RoD8C9EeA/gjQHwH6I0B/BOiPAP0RoD8C9EeA/gjQH/n+/hDgGwT4BgG+QYBvEOAbBPgGAb5BgG8Q4BsE+AYBvkGAbxDgGwT4BgG+QYBvEOAbBPgGAb5BgG8Q4BsE+AYBvkGAbxDgGwT4BgG+QYBvEOAbBPgGAb5BgG8Q4BsE+AYBvkGAbxDgGwT4BgG+QYBvEOAbBPgGAb5BgG8Q4BsE+AYBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2AQBNkGATRBgEwTYBAE2QYBNEGATBNgEATZBgE0QYBME2IQ/M4A5NTCnBub0+7oQcBYCnIUAZyHAWQhwFgKchQBnIcBZCHAWApyFAGchwFkIcBYCnIUAZ/FnBjCnBubUwJx+VxcaMCMGzIgBM2LAjBgwIwbMiAEzYsCMGDAjBsyIATNiwIwYMCMGzIgBM2LAjBgwIwbMiAEzYsCMGDAjBsyIATNiwIwYMCMGzIgBM2LAjBgwIwbMiAEzYsCMGPAeBryHAe9hwHsY8B4GvIcB72HAexjwHga8hwHvYcB7GPAeBv4/CwNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTFgRgyYEQNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTFgRgyYEQNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTFgRgyYEQNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTFgRgyYEQNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTFgRgyYEQNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTFgRgyYEQNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTFgRgyYEQNmxIAZMWBGDJgRA2bEgBkxYEYMmBEDZsSAGTHgPQx4DwPew4D3MOA9DHgPA97DgPcw4D0MeA8D3sOA9zDgPQx4DwPew4D3MOA9DHgPA97DgPcw4D0MeA8D3sOA9zDgPQx4DwPew4D3MOA9DHgPA97DgPcw4D0MeA8D3sOA9zDgPQx4DwPew4D3MOA9DHgPA97DgPcw4D0MeA8D3sOA9wjgPQJ4jwDeI4D3COA9AniPAN4jgPcI4D0CeI8A3iOA9wjgPQJ4jwDeI4D3COA9AniPAN4jgPcI4D0CeI8A3iOA9wjgPQJ4jwDeI4D3COA9AniPAN4jgPcI8H+EBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBDAjAcxIADMSwIwEMCMBzEgAMxLAjAQwIwHMSAAzEsCMBPh/RgK4kwDuJIA7CeBOAriTAO4kgDsJ4E4CuJMA7iSAOwngTgK4kwDuJIA7CeBOAriTAO4kgDsJ4E4CuJMA7iSAOwngTgK4kwDuJIA7CeBOAriTAO4kgDsJ4E4CuJMA7iSAOwngTgK4kwDuJIA7CeBOAriTAO4kgDsJ4E4CuJMA7iSAO0m3O3l/tdmfdvcvP/jh7nn3eNwfTpurza+749Pn1GUdMyeL5+24nf3p0/8A+hQcUg==",
    aquilo  = "",  -- TODO: Aquilo variant with extra solar (falls back to default for now).
}

--- Best-effort planet key for an MTS surface name (e.g. "mts-aquilo-3",
--- "team-3-nauvis"). Returns nil if no known planet fragment matches.
function M.planet_of(surface_name)
    local lowered = surface_name:lower()
    for _, planet in ipairs(PLANETS) do
        if lowered:find(planet, 1, true) then return planet end
    end
    return nil
end
local planet_of = M.planet_of

--- Returns the blueprint string for a surface, or "" if none is configured.
function M.for_surface(surface)
    local planet = planet_of(surface.name)
    if planet and M.blueprints[planet] and M.blueprints[planet] ~= "" then
        return M.blueprints[planet]
    end
    return M.blueprints.default
end

return M
