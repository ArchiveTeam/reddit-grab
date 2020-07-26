dofile("table_show.lua")
dofile("urlcode.lua")
JSON = (loadfile "JSON.lua")()

local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false

local posts = {}
local requested_children = {}
local thumbs = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

load_json_file = function(file)
  if file then
    return JSON:decode(file)
  else
    return nil
  end
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

processed = function(url)
  if downloaded[url] or addedtolist[url] then
    return true
  end
  return false
end

allowed = function(url, parenturl)
  local match = string.match(url, "^https?://[^%.]+%.thumbs%.redditmedia%.com/([^%.]+)%.")
  if match
    and parenturl
    and string.match(parenturl, "^https?://www%.reddit%.com/api/info%.json%?id=") then
    thumbs[match] = true
  end

  if match and not thumbs[match] then
    return false
  end

  if string.match(url, "'+")
    or string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
    or string.match(url, "^https?://[^/]*reddit%.com/[^%?]+%?context=[0-9]+&depth=[0-9]+")
    or string.match(url, "^https?://[^/]*reddit%.com/[^%?]+%?depth=[0-9]+&context=[0-9]+")
    or string.match(url, "^https?://[^/]*reddit%.com/login")
    or string.match(url, "^https?://[^/]*reddit%.com/register")
    or string.match(url, "%?sort=")
    or string.match(url, "%?limit=500$")
    or string.match(url, "%?ref=readnext$")
    or string.match(url, "^https?://[^/]*reddit%.app%.link/")
    or string.match(url, "^https?://out%.reddit%.com/r/")
    or string.match(url, "^https?://emoji%.redditmedia%.com/")
    or string.match(url, "^https?://styles%.redditmedia%.com/")
    or string.match(url, "^https?://[^%.]+%.redd%.it/award_images/")
    or (
      string.match(url, "^https?://gateway%.reddit%.com/")
      and not string.match(url, "/morecomments/")
    )
    or string.match(url, "/%.rss$")
    or (
      parenturl
      and string.match(url, "^https?://amp%.reddit%.com/")
    )
    or (
      item_type == "posts"
      and string.match(url, "^https?://[^/]*reddit%.com/r/[^/]+/comments/[0-9a-z]+/[^/]+/[0-9a-z]+/?$")
    )
    or (
      parenturl
      and string.match(parenturl, "^https?://[^/]*reddit%.com/r/[^/]+/duplicates/")
      and string.match(url, "^https?://[^/]*reddit%.com/r/[^/]+/duplicates/")
    ) then
    return false
  end

  local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end

  if url .. "/" == parenturl then
    return false
  end

  if (string.match(url, "^https?://[^/]*redditmedia%.com/")
      or string.match(url, "^https?://old%.reddit%.com/api/morechildren$")
      or string.match(url, "^https?://v%.redd%.it/")
      or string.match(url, "^https?://i%.redd%.it/")
      or string.match(url, "^https?://[^%.]*preview%.redd%.it/.")
    )
    and not string.match(item_type, "comment") then
    return true
  end

  for s in string.gmatch(url, "([a-z0-9]+)") do
    if posts[s] then
      return true
    end
  end
  
  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]

  if item_type == "comments" then
    return false
  end

  if string.match(url, "[<>\\%*%$;%^%[%],%(%){}]")
    or string.match(url, "^https?://[^/]*redditstatic%.com/")
    or string.match(url, "^https?://old%.reddit%.com/static/")
    or string.match(url, "^https?://www%.reddit%.com/static/")
    or string.match(url, "^https?://styles%.redditmedia%.com/")
    or string.match(url, "^https?://emoji%.redditmedia%.com/")
    or string.match(url, "/%.rss$") then
    return false
  end

  if string.match(parent["url"], "^https?://old%.reddit%.com/comments/[a-z0-9]+") then
    return true
  end

  if not processed(url)
      and (allowed(url, parent["url"]) or (allowed(parent["url"]) and html == 0)) then
    addedtolist[url] = true
    return true
  end
  
  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil
  
  downloaded[url] = true

  local function check(urla)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.gsub(string.match(url, "^(.-)%.?$"), "&amp;", "&")
    if not processed(url_)
        and string.match(url_, "^https?://.+")
        and allowed(url_, origurl)
        and not (string.match(url_, "[^/]$") and processed(url_ .. "/")) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/\\/") then
      check(string.match(url, "^(https?:)") .. string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(string.match(url, "^(https?:)") .. newurl)
    elseif string.match(newurl, "^\\/") then
      check(string.match(url, "^(https?://[^/]+)") .. string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)") .. newurl)
    elseif string.match(newurl, "^%./") then
      checknewurl(string.match(newurl, "^%.(.+)"))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(string.match(url, "^(https?://[^%?]+)") .. newurl)
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^data:")
      or string.match(newurl, "^%${")) then
      check(string.match(url, "^(https?://.+/)") .. newurl)
    end
  end

  if string.match(url, "^https?://www%.reddit%.com/") then
    check(string.gsub(url, "^https?://www%.reddit%.com/", "https://old.reddit.com/"))
  --elseif string.match(url, "^https?://old%.reddit%.com/") then
  --  check(string.gsub(url, "^https?://old%.reddit%.com/", "https://www.reddit.com/"))
  end

  if allowed(url)
    and status_code < 300
    and not string.match(url, "^https?://[^/]*redditmedia%.com/")
    and not string.match(url, "^https?://[^/]*redditstatic%.com/")
    and not string.match(url, "^https?://out%.reddit%.com/")
    and not string.match(url, "^https?://[^%.]*preview%.redd%.it/")
    and not string.match(url, "^https?://i%.redd%.it/")
    and not string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]*%.ts")
    and not string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]*%.mp4") then
    html = read_file(file)
    if string.match(url, "^https?://old%.reddit%.com/api/morechildren$") then
      html = string.gsub(html, '\\"', '"')
    elseif string.match(url, "^https?://old%.reddit%.com/r/[^/]+/comments/")
      or string.match(url, "^https?://old%.reddit%.com/r/[^/]+/duplicates/") then
      html = string.gsub(html, "<div%s+class='spacer'>%s*<div%s+class=\"titlebox\">.-</div>%s*</div>%s*<div%s+class='spacer'>%s*<div%s+id=\"ad_[0-9]+\"%s*class=\"ad%-container%s*\">", "")
    end    
    if string.match(url, "^https?://old%.reddit%.com/") then
      for s in string.gmatch(html, "(return%s+morechildren%(this,%s*'[^']+',%s*'[^']+',%s*'[^']+',%s*'[^']+'%))") do
        local link_id, sort, children, limit_children = string.match(s, "%(this,%s*'([^']+)',%s*'([^']+)',%s*'([^']+)',%s*'([^']+)'%)$")
        local id = string.match(children, "^([^,]+)")
        local subreddit = string.match(html, 'data%-subreddit="([^"]+)"')
        local post_data = 
          "link_id=" .. link_id ..
          "&sort=" .. sort ..
          "&children=" .. string.gsub(children, ",", "%%2C") ..
          "&id=t1_" .. id ..
          "&limit_children=" .. limit_children ..
          "&r=" .. subreddit ..
          "&renderstyle=html"
        if not requested_children[post_data] then
          requested_children[post_data] = true
          table.insert(urls, {url="https://old.reddit.com/api/morechildren",
                              post_data=post_data})
        end
      end
    elseif string.match(url, "^https?://www%.reddit%.com/r/[^/]+/comments/[^/]")
      or string.match(url, "^https?://www%.reddit%.com/comments/[^/]")
      or string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/t3_[^%?]") then
      for s in string.gmatch(html, '"token"%s*:%s*"([^"]+)"') do
        local post_data = '{"token":"' .. s .. '"}'
        local comment_id = string.match(url, "^https?://www%.reddit%.com/r/[^/]+/comments/([^/]+)")
        if comment_id == nil then
          comment_id = string.match(url, "^https?://www%.reddit%.com/comments/([^/]+)")
        end
        if comment_id == nil then
          comment_id = string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/t3_([^%?]+)")
        end
        if comment_id == nil then
          print("Could not find comment ID.")
          abortgrab = true
        end
        if not requested_children[post_data] then
          requested_children[post_data] = true
          table.insert(urls, {url=
            "https://gateway.reddit.com/desktopapi/v1/morecomments/t3_" .. comment_id .. 
            "?emotes_as_images=true" ..
            "&rtj=only" ..
            "&allow_over18=1" ..
            "&include=",
            post_data=post_data
          })
        end
      end
    end
    if string.match(url, "^https?://gateway%.reddit%.com/desktopapi/v1/morecomments/") then
      for s in string.gmatch(html, '"permalink"%s*:%s*"([^"]+)"') do
        check("https?://www.reddit.com" .. s)
      end
    end
    if string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]+%.mpd") then
      for s in string.gmatch(html, "<BaseURL>([^<]+)</BaseURL>") do
        checknewshorturl(s)
      end
    end
    if string.match(url, "^https?://v%.redd%.it/[^/]+/[^%.]+%.m3u8") then
      for s in string.gmatch(html, "(.-)\n") do
        if not string.match(s, "^#") then
          checknewshorturl(s)
        end
      end
    end
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. " \n")
  io.stdout:flush()

  local match = string.match(url["url"], "^https?://www%.reddit.com/api/info%.json%?id=t[0-9]_([a-z0-9]+)$")
  if match then
    posts[match] = true
  end

  if status_code == 204 then
    return wget.actions.EXIT
  end

  if (status_code >= 300 and status_code <= 399) then
    local newloc = string.match(http_stat["newloc"], "^([^#]+)")
    if string.match(newloc, "^//") then
      newloc = string.match(url["url"], "^(https?:)") .. string.match(newloc, "^//(.+)")
    elseif string.match(newloc, "^/") then
      newloc = string.match(url["url"], "^(https?://[^/]+)") .. newloc
    elseif not string.match(newloc, "^https?://") then
      newloc = string.match(url["url"], "^(https?://.+/)") .. newloc
    end
    if processed(newloc) or not allowed(newloc, url["url"]) then
      return wget.actions.EXIT
    end
  end
  
  if (status_code >= 200 and status_code <= 399) then
    downloaded[url["url"]] = true
    downloaded[string.gsub(url["url"], "https?://", "http://")] = true
  end

  if abortgrab then
    io.stdout:write("ABORTING...\n")
    return wget.actions.ABORT
  end
  
  if status_code >= 500
      or (status_code >= 400 and status_code ~= 403 and status_code ~= 404)
      or status_code  == 0 then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 8
    if not allowed(url["url"]) then
        maxtries = 0
    end
    if tries >= maxtries then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      if allowed(url["url"]) then
        return wget.actions.ABORT
      else
        return wget.actions.EXIT
      end
    end
    os.execute("sleep " .. math.floor(math.pow(2, tries)))
    tries = tries + 1
    return wget.actions.CONTINUE
  end

  if string.match(url["url"], "^https?://[^/]+%.reddit%.com/api/info%?id=t[0-9]_[a-z0-9]+$") then
    return wget.actions.EXIT
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end

wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab then
    return wget.exits.IO_FAIL
  end
  return exit_status
end
