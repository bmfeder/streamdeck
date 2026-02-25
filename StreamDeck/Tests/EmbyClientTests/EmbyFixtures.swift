import Foundation

enum EmbyFixtures {

    static let authResponse = """
    {
        "User": {
            "Id": "user-123",
            "Name": "testuser"
        },
        "AccessToken": "abc-token-xyz"
    }
    """

    static let librariesResponse = """
    {
        "Items": [
            {"Id": "lib-1", "Name": "Movies", "CollectionType": "movies"},
            {"Id": "lib-2", "Name": "TV Shows", "CollectionType": "tvshows"},
            {"Id": "lib-3", "Name": "Music", "CollectionType": "music"}
        ]
    }
    """

    static let emptyLibrariesResponse = """
    {"Items": []}
    """

    static let moviesResponse = """
    {
        "Items": [
            {
                "Id": "movie-1",
                "Name": "Inception",
                "Type": "Movie",
                "Overview": "A mind-bending thriller",
                "ProductionYear": 2010,
                "CommunityRating": 8.8,
                "RunTimeTicks": 88800000000,
                "ImageTags": {"Primary": "tag-abc"},
                "GenreItems": [{"Name": "Action"}, {"Name": "Sci-Fi"}],
                "UserData": {"PlaybackPositionTicks": 0, "Played": false}
            },
            {
                "Id": "movie-2",
                "Name": "Avatar",
                "Type": "Movie",
                "ProductionYear": 2009,
                "RunTimeTicks": 97200000000,
                "GenreItems": [{"Name": "Sci-Fi"}]
            }
        ],
        "TotalRecordCount": 2
    }
    """

    static let seriesResponse = """
    {
        "Items": [
            {
                "Id": "series-1",
                "Name": "Breaking Bad",
                "Type": "Series",
                "Overview": "A chemistry teacher turns drug lord",
                "ProductionYear": 2008,
                "CommunityRating": 9.5,
                "ImageTags": {"Primary": "tag-bb"},
                "GenreItems": [{"Name": "Drama"}, {"Name": "Crime"}]
            }
        ],
        "TotalRecordCount": 1
    }
    """

    static let episodesResponse = """
    {
        "Items": [
            {
                "Id": "ep-1",
                "Name": "Pilot",
                "Type": "Episode",
                "SeriesId": "series-1",
                "SeriesName": "Breaking Bad",
                "ParentIndexNumber": 1,
                "IndexNumber": 1,
                "RunTimeTicks": 35400000000,
                "Overview": "Walter White begins his journey",
                "UserData": {"PlaybackPositionTicks": 150000000000, "Played": false}
            },
            {
                "Id": "ep-2",
                "Name": "Cat's in the Bag...",
                "Type": "Episode",
                "SeriesId": "series-1",
                "ParentIndexNumber": 1,
                "IndexNumber": 2,
                "RunTimeTicks": 28800000000
            }
        ],
        "TotalRecordCount": 2
    }
    """

    static let singleItemWithResume = """
    {
        "Id": "movie-1",
        "Name": "Inception",
        "Type": "Movie",
        "RunTimeTicks": 88800000000,
        "UserData": {"PlaybackPositionTicks": 36000000000, "Played": false}
    }
    """

    static let emptyItemsResponse = """
    {"Items": [], "TotalRecordCount": 0}
    """

    static let movieMinimal = """
    {
        "Id": "m-min",
        "Name": "Minimal Movie",
        "Type": "Movie"
    }
    """
}
