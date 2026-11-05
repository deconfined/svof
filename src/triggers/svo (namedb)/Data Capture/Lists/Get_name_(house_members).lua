local match = getColorWildcard(14)

if match then
  temp_name_list[#temp_name_list + 1] = {
    name = match[1],
  }
end