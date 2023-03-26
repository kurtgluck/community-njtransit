"""
Applet: NJ Transit Dpature Vision
Summary: Shows the next departing trains of a station
Description: Shows the departing NJ Transit Trains of a selected station
Author: jason-j-hunt
"""

load("cache.star", "cache")
load("encoding/json.star", "json")
load("html.star", "html")
load("http.star", "http")
load("render.star", "render")
load("schema.star", "schema")
#KAG - need time 
load("time.star", "time")

#URL TO NJ TRANSIT DEPARTURE VISION WEBSITE
NJ_TRANSIT_DV_URL = "https://www.njtransit.com/dv-to"
DEFAULT_STATION = "New York Penn Station"
#KAG - default destination AND default time to get to station
DEFAULT_DESTINATION_STATION = "Glen Ridge Station"
DEFAULT_SKIP_BEFORE = "0"

STATION_CACHE_KEY = "stations"
STATION_CACHE_TTL = 604800  #1 Week

DEPARTURES_CACHE_KEY = "departures"
DEPARTURES_CACHE_TTL = 60  # 1 minute

#KAG - TIMEZONE
TRANSIT_TIME_ZONE = "America/New_York"
###TRANSIT_TIME_LAYOUT = "20060102 15:04"
#https://www.njtransit.com/train-to?origin=NY%20Penn%20Station&destination=Glen%20Ridge%20Station&date=03%2F20%2F2023
NJ_TRANSIT_FROM_TO_DATE_URL = "https://www.njtransit.com/train-to?origin={}&destination={}&date={}"
NJ_TRANSIT_FROM_TO_URL = "https://www.njtransit.com/train-to?origin={}&destination={}"

#KAG - The app doesnt cache the actual train_view information - should be for a minute?
# this looks like its a codeing error.  the TTL of the DEPARTURES_CACHE_KEY
# makes it look like its the actual departure data, but instead its the translated
# station options?
#    Also - the key would have to include the station name that we
#    are grabing the data for


TIMEZONE = "America/New_York"

#DISPLAYS FIRST 3 Departures by default
DISPLAY_COUNT = 2

#Gets Hex color code for a given service line
COLOR_MAP = {
    #Rail Lines
    "ACRL": "#2e55a5",  #Atlantic City
    "AMTK": "#ffca18",  #Amtrak
    "BERG": "#c3c3c3",  #Bergen
    "MAIN": "#fbb600",  #Main-Bergen Line
    "MOBO": "#c26366",  #Montclair-Boonton
    "M&E": "#28943b",  #Morris & Essex
    "NEC": "#f54f5e",  #Northeast Corridor
    "NJCL": "#339cdb",  #North Jersey Coast
    "PASC": "#a34e8a",  #Pascack Valley
    "RARV": "#ff9315",  #Raritan Valley
}

DEFAULT_COLOR = "#908E8E"  #If a line doesnt have a mapping fall back to this

def main(config):
    selected_station = config.get("station", DEFAULT_STATION)
    #KAG - start
    selected_destination = config.get("stationdestination", DEFAULT_DESTINATION_STATION)

    filter_trains_by_destination = selected_destination != selected_station
    trains_to_destination = get_trains_from_to(filter_trains_by_destination, selected_station, selected_destination)
    #KAG - end

    departures = get_departures_for_station(selected_station)

    #KAG - add list of trains we might want
    #KAG - flag saying if we should use that list
    rendered_rows = render_departure_list(departures, filter_trains_by_destination, trains_to_destination )
    #rendered_rows = render_departure_list(departures)

    return render.Root(
        delay = 75,
        max_age = 60,
        child = rendered_rows,
    )

#def render_departure_list(departures):
def render_departure_list(departures, filter_trains_by_destination, trains_to_destination):
    """
    Renders a given lists of departures
    If filter_trains_by_destination is True then will only render trains in the dictionary trains_to_destination
    """

    ### I know that I am doing extra work by not stoping the loop when DISPLAY_COUNT is exceeded - this is
    ### to aid my debugging.  TODO improve this

    render_count = 0 
    
    rendered = []

    for d in departures:
        train_number = d.train_number
        if should_train_be_rendered(filter_trains_by_destination, trains_to_destination, train_number, render_count):
            render_count = render_count + 1
            rendered.append(render_departure_row(d))

    return render.Column(
        expanded = True,
        main_align = "start",
        children = [
            rendered[0],
            render.Box(
                width = 64,
                height = 1,
                color = "#666",
            ),
            rendered[1],
        ],
    )

def should_train_be_rendered(filter_trains_by_destination, trains_to_destination, train_number, rendered_so_far):
    """
    if filter_trains_by_destination is False then return True
    Otherwise check to see if this train_number is in the dictionary trains_to_destination
    """

    print("should_train_be_rendered({},{},{},{})".format(filter_trains_by_destination, trains_to_destination, train_number, rendered_so_far ))

    if rendered_so_far > DISPLAY_COUNT:
        print("should_train_be_rendered() -> {} rendered exceeds {} DONT".format(rendered_so_far,DISPLAY_COUNT))
        return False

    if not(filter_trains_by_destination):
        print("should_train_be_rendered() -> Dont filter so YES")
        return True

    dict_entry = trains_to_destination.get(train_number)
    if dict_entry == None:
        print("should_train_be_rendered() -> Train Not Found dont render")
        return False

    print("should_train_be_rendered() -> Train {} Found render".format(train_number))
    return True

def render_departure_row(departure):
    """
    Creates a Row and adds needed children objects
    for a single departure.
    """
    background_color = render.Box(width = 22, height = 11, color = COLOR_MAP.get(departure.service_line, DEFAULT_COLOR))
    destination_text = render.Marquee(
        width = 36,
        child = render.Text(departure.destination, font = "Dina_r400-6", offset = -2, height = 7),
    )

    departing_in_text = render.Text(departure.departing_in, color = "#f3ab3f")

    #If we have a Track Number append and make it a scroll marquee
    if departure.track_number != None:
        depart = "{} - Track {}".format(departure.departing_in, departure.track_number)
        departing_in_text = render.Marquee(
            width = 36,
            child = render.Text(depart, color = "#f3ab3f"),
        )

    if departure.departing_in.startswith("at"):
        departing_in_text = render.Marquee(
            width = 36,
            child = render.Text(departure.departing_in, color = "#f3ab3f"),
        )

    child_train_number = render.Text(departure.train_number, font = "CG-pixel-4x5-mono")

    if len(departure.train_number) > 4:
        child_train_number = render.Marquee(child = child_train_number)

    train_number = render.Box(
        color = "#0000",
        width = 22,
        height = 11,
        child = child_train_number,
    )

    stack = render.Stack(children = [
        background_color,
        train_number,
    ])

    column = render.Column(
        children = [
            destination_text,
            departing_in_text,
        ],
    )

    return render.Row(
        expanded = True,
        main_align = "space_evenly",
        cross_align = "center",
        children = [
            stack,
            column,
        ],
    )

def get_schema():
    options = getStationListOptions()
    
    #KAG
    #TODO Do I have to change the version since i am adding to the schema?
    #
    #Added second Field to the Schema: Optional station you wish to go to.
    #Output will be filtered so only trains that go to the destination will be in the output, including transfers.
    #If you want origional behavor then make the destination the same as the departing station.
    #
    
    return schema.Schema(
        version = "1",
        fields = [
            schema.Dropdown(
                id = "station",
                name = "Departing Station",
                desc = "The NJ Transit Station to get departure schedule for.",
                icon = "train",
                default = options[0].value,
                options = options,
            ),
            schema.Dropdown(
                id = "stationdestination",
                name = "Destination Station",
                desc = "If different then Departing - then only show trains that get here (including connections).",
                icon = "arrowRightToCity",
                default = options[0].value,
                options = options,
            ),
        ],
    )

def get_departures_for_station(station):
    """
    Function gets all depatures for a given station
    returns a list of structs with the following fields

    depature_item struct:
        departing_at: string
        destination: string
        service_line: string
        train_number: string
        track_number: string
        departing_in: string
    """
    #print("Getting departures for '%s'" % station)
    print("========THEIR THERE======")
    
    print("get_departures_for_station({}) Found '{}' departures".format(station,departures.len()))

    result = []

    for index in range(0, departures.len()):
        departure = departures.eq(index)
        item = extract_fields_from_departure(departure)
        result.append(item)

        #if len(result) == DISPLAY_COUNT:
        #    return result

    return result

def extract_fields_from_departure(departure):
    """
    Function Extracts necessary data from HTML of a given depature
    """
    data = departure.find(".media-body").first()

    departure_time = get_departure_time(data)
    destination_name = get_destination_name(data)
    service_line = get_service_line(data)
    train_number = get_train_number(data)
    track_number = get_track_number(data)
    departing_in = get_real_time_estimated_departure(data, departure_time)

    #print(
    #    "{}\t{}\t{}\t{}\t{}\t{}\n".format(
    #        departure_time,
    #        destination_name,
    #        service_line,
    #        train_number,
    #        track_number,
    #        departing_in,
    #    ),
    #)

    return struct(
        departing_at = departure_time,
        destination = destination_name,
        service_line = service_line,
        train_number = train_number,
        track_number = track_number,
        departing_in = departing_in,
    )

def get_departure_time(data):
    """
    Function gets depature time for a given depature
    """
    time_string = data.find(".d-block.ff-secondary--bold.flex-grow-1.h2.mb-0").first().text().strip()
    return time_string

def get_service_line(data):
    """
    Function gets the service line the train is running on
    """
    nodes = data.find(".media-body").first().find(".mb-0")
    string = nodes.eq(1).text().strip().split()
    service_line = string[0].strip()

    return service_line

def get_train_number(data):
    """
    Function gets the train number from a given depature
    """
    nodes = data.find(".media-body").first().find(".mb-0")
    srvc_train_number = nodes.eq(1).text().strip().split()
    train_number = srvc_train_number[2].strip()
    return train_number

def get_destination_name(data):
    """
    Function gets the destation froma  given depature
    """
    nodes = data.find(".media-body").first().find(".mb-0")
    destination_name = nodes.eq(0).text().strip().replace("\\u2708", "EWR").upper()
    return destination_name

def get_real_time_estimated_departure(data, scheduled_time):
    """
    Will attempt to get given departing time from nj transit
    If not availble will return the in X min via the scheduled
    Departure time - time.now()
    """
    nodes = data.find(".media-body").first().find(".mb-0")
    node = nodes.eq(2)

    departing_in = ""

    if node != None:
        departing_in = node.text().strip().removeprefix("in ")

    #If we cant get from NJT return scheduled Departure time
    if len(departing_in) == 0:
        departing_in = "at {}".format(scheduled_time)

    return departing_in

def get_track_number(data):
    """
    Returns the track number the train will be departing from.
    May not be availble until about 10 minutes before scheduled departure time.
    """
    node = data.find(".align-self-end.mb-0").first()

    if node != None:
        text = node.text().strip().split()
        if len(text) > 1:
            track = text[1].strip()
        else:
            track = None
    else:
        track = None

    return track

def fetch_stations_from_website():
    """
    Function fetches trains station list from NJ Transit website
    To be used for creating Schema option list
    """
    result = []

    nj_dv_page_response_body = cache.get(DEPARTURES_CACHE_KEY)

    if nj_dv_page_response_body == None:
        nj_dv_page_response = http.get(NJ_TRANSIT_DV_URL)

        if nj_dv_page_response.status_code != 200:
            #print("Got code '%s' from page response" % nj_dv_page_response.status_code)
            return result

        nj_dv_page_response_body = nj_dv_page_response.body()
              
        cache.set(DEPARTURES_CACHE_KEY, nj_dv_page_response.body(), DEPARTURES_CACHE_TTL)

    selector = html(nj_dv_page_response_body)
    stations = selector.find(".vbt-autocomplete-list.list-unstyled.position-absolute.pt-1.shadow.w-100").first().children()

    #print("Got response of '%s' stations" % stations.len())

    for index in range(0, stations.len()):
        station = stations.eq(index)
        station_name = station.find("a").first().text()

        #print("Found station '%s' from page response" % station_name)
        result.append(station_name)

    return result

def getStationListOptions():
    """
    Creates a list of schema options from station list
    """
    options = []
    cache_string = cache.get(STATION_CACHE_KEY)

    stations = None

    if cache_string != None:
        stations = json.decode(cache_string)

    if stations == None:
        stations = fetch_stations_from_website()
        cache.set(STATION_CACHE_KEY, json.encode(stations), STATION_CACHE_TTL)

    for station in stations:
        options.append(create_option(station, station))

    return options

def create_option(display_name, value):
    """
    Helper function to create a schema option of a given display name and value
    """
    return schema.Option(
        display = display_name,
        value = value,
    )

def get_trains_from_to(filter_trains_by_destination, from_station, to_station):
    """
    Function gets trains from from_station to to_station
    if filter_trains_by_destination is FALSE then just return an empty list
    returns a hashmap? of train numbers of the form "#NNNN" ie:#6233
    That is train #6233 leaves from from_station and either goes to, or connects to to_station
    """
    print("Get trains from '{}' to '{}' ".format(from_station,to_station))

    # https://www.njtransit.com/train-
    #NJ_TRANSIT_FROM_TO_DATE_URL = "https://www.njtransit.com/train-to?origin={}&destination={}&date={}"
    #NJ_TRANSIT_FROM_TO_URL = "https://www.njtransit.com/train-to?origin={}&destination={}"

    cache_key = "from={}/to={}".format(from_station,to_station)
    cache_ttl  = 60 * 30 # 1/2 hour

    #trains = cache.get(cache_key)
    #if trains != None:
    #    print("get_trains_from_to cache hit {}".format(cache_key))
    #    return trains
              
    trains = dict()
    if not(filter_trains_by_destination): return trains
              
    from_to_url = NJ_TRANSIT_FROM_TO_URL.format(from_station.replace(" ","%20"),to_station.replace(" ","%20"))
    print("==================URL")
    print("from_to_url='{}'".format(from_to_url))
    print("==================URL")

    nj_page_response = http.get(from_to_url)
    #nj_page_response = http.post(from_to_url)

    #print("PR:::::: {} ::::::PR:::::::".format(nj_page_response))
    
    if nj_page_response.status_code != 200:
        print("Got code '{}' from page response on {}".format( nj_page_response.status_code,from_to_url))
        return trains

    selector = html(nj_page_response.body())

    print("=======================BODY")

    print(" BODY={}=BODY".format(nj_page_response.body()))

    print("=======================BODYS")

    print(" BODYS={}=BODYS".format(selector))

    #HANGS print("=======================JSON")

    ##print(" JSON={}=JSON".format(nj_page_response.json()))

    print("=======================FIND")

    #key = ".media.border.flex-column.flex-md-row.mb-3.no-gutters.p-3.rounded"
    #key = ".media.border.flex-column.flex-md-row.mb-3.no-gutters.p-3.rounded.bg-light"
    #key = "media.border.flex-column.flex-md-row.mb-3.no-gutters.p-3.rounded.bg-light"
    #key = "media.border.flex-column.flex-md-row.mb-3.no-gutters.p-3.rounded"
    key = ".media-aside.mb-2.mb-md-0.align-self-start.col-12.col-md-4.order-0.order-md-1"
    
    thetrains = selector.find(key)

    #class="media-aside mb-2 mb-md-0 align-self-start col-12 col-md-4 order-0 order-md-1"



    print("Found '{}' trains on {}".format(thetrains.len(),from_to_url))

    for index in range(0, thetrains.len()):
        atrain = thetrains.eq(index)
        atrain_tuple = extract_fields_from_schedule(atrain)
        if atrain_tuple == None :
              print("Hum train row {} from {} returned None".format(index,from_to_url))
        else:
              print("dictionary load '{}'='{}'".format(atrain_tuple[1],atrain_tuple[0]))
              trains[atrain_tuple[1]] = atrain_tuple[0]

    #TODO cache_ttl should be min(# seconds left in the day -1, cache_ttl)
    #cache.set(cache_key, trains, cache_ttl)      

    return trains
            
def extract_fields_from_schedule(aschedule):
    """
    Function Extracts necessary data from HTML of a given train on from to 
    """

    #"
    #    Montclair-Boonton
    #   
    #    #6251
    #   "

    if aschedule == None:
        print("extract_fields_from_schedule P1  passed None")
        return None 
   
    data = aschedule.find(".media-body").first()
    
    if data == None:
        print("extract_fields_from_schedule P2  .media-body Not found")
        return None

    the_string = data.find(".text-md-right.w-100").first().text().strip()
    
    if the_string == None:
        print("extract_fields_from_schedule P3  .text-md-right.w-100 Not found")
        return None

    before_sep_after = the_string.partiton("#")
    
    if before_sep_after == None:
        print("extract_fields_from_schedule P4  cant partition on #")
        return None
    
    theline = before_sep_after[0].lstrip().strip()
    sep = before_sep_after[1]
    thetrainnumber = before_sep_after[2].lstrip().strip()

    print("extract_fields_from_schedule line='{}' sep='{}' #='{}'",theline,sep,thetrainnumber)

    return ( theline , thetrainnumber )
    
