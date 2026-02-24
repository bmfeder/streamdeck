import Foundation

// swiftlint:disable line_length

/// JSON fixture strings for all Xtream API endpoints.
enum XtreamFixtures {

    // MARK: - Authentication

    static let authSuccess = """
    {
        "user_info": {
            "username": "testuser",
            "password": "testpass",
            "status": "Active",
            "auth": 1,
            "exp_date": "1893456000",
            "is_trial": "0",
            "active_cons": "1",
            "max_connections": "2",
            "created_at": "1704067200",
            "allowed_output_formats": ["m3u8", "ts"]
        },
        "server_info": {
            "url": "provider.example.com",
            "port": "8080",
            "https_port": "8443",
            "server_protocol": "http",
            "rtmp_port": "8088",
            "timezone": "America/New_York",
            "timestamp_now": "1709251200",
            "time_now": "2024-03-01 12:00:00"
        }
    }
    """

    static let authFailed = """
    {
        "user_info": {
            "username": "baduser",
            "password": "badpass",
            "status": "Disabled",
            "auth": 0,
            "exp_date": null,
            "is_trial": "0",
            "active_cons": "0",
            "max_connections": "0",
            "allowed_output_formats": []
        },
        "server_info": {
            "url": "",
            "port": "0",
            "https_port": "0",
            "server_protocol": "http",
            "rtmp_port": "0",
            "timezone": "UTC"
        }
    }
    """

    static let authExpired = """
    {
        "user_info": {
            "username": "testuser",
            "password": "testpass",
            "status": "Expired",
            "auth": 1,
            "exp_date": "1609459200",
            "is_trial": "0",
            "active_cons": "0",
            "max_connections": "1",
            "created_at": "1577836800",
            "allowed_output_formats": ["m3u8"]
        },
        "server_info": {
            "url": "provider.example.com",
            "port": "8080",
            "https_port": "8443",
            "server_protocol": "http",
            "rtmp_port": "8088",
            "timezone": "UTC",
            "timestamp_now": "1709251200",
            "time_now": "2024-03-01 12:00:00"
        }
    }
    """

    /// All numeric fields come as ints instead of strings — tests lenient decoding.
    static let authNumericFields = """
    {
        "user_info": {
            "username": "testuser",
            "password": "testpass",
            "status": "Active",
            "auth": 1,
            "exp_date": 1893456000,
            "is_trial": 0,
            "active_cons": 1,
            "max_connections": 2,
            "created_at": 1704067200,
            "allowed_output_formats": ["m3u8", "ts"]
        },
        "server_info": {
            "url": "provider.example.com",
            "port": 8080,
            "https_port": 8443,
            "server_protocol": "http",
            "rtmp_port": 8088,
            "timezone": "UTC"
        }
    }
    """

    static let authNullExpDate = """
    {
        "user_info": {
            "username": "testuser",
            "password": "testpass",
            "status": "Active",
            "auth": 1,
            "exp_date": null,
            "is_trial": "0",
            "active_cons": "1",
            "max_connections": "1",
            "allowed_output_formats": ["m3u8"]
        },
        "server_info": {
            "url": "provider.example.com",
            "port": "8080",
            "https_port": "8443",
            "server_protocol": "http",
            "rtmp_port": "8088",
            "timezone": "UTC"
        }
    }
    """

    // MARK: - Categories

    static let liveCategories = """
    [
        {"category_id": "1", "category_name": "Sports", "parent_id": 0},
        {"category_id": "2", "category_name": "News", "parent_id": 0},
        {"category_id": "3", "category_name": "Football", "parent_id": 1}
    ]
    """

    static let emptyArray = "[]"

    // MARK: - Live Streams

    static let liveStreams = """
    [
        {
            "num": 1,
            "name": "ESPN HD",
            "stream_type": "live",
            "stream_id": 1001,
            "stream_icon": "https://cdn.example.com/espn.png",
            "epg_channel_id": "ESPN.us",
            "added": "1704067200",
            "category_id": "1",
            "custom_sid": "",
            "tv_archive": 0,
            "direct_source": "",
            "tv_archive_duration": 0
        },
        {
            "num": 2,
            "name": "CNN International",
            "stream_type": "live",
            "stream_id": 1002,
            "stream_icon": "",
            "epg_channel_id": "CNN.us",
            "added": "1704067200",
            "category_id": "2",
            "custom_sid": "",
            "tv_archive": 1,
            "direct_source": "",
            "tv_archive_duration": "72"
        }
    ]
    """

    // MARK: - VOD Streams

    static let vodStreams = """
    [
        {
            "num": 1,
            "name": "The Matrix",
            "stream_type": "movie",
            "stream_id": 5001,
            "stream_icon": "https://cdn.example.com/matrix.jpg",
            "rating": "8.7",
            "added": "1704067200",
            "category_id": "10",
            "container_extension": "mkv",
            "custom_sid": "",
            "direct_source": ""
        },
        {
            "num": 2,
            "name": "Inception",
            "stream_type": "movie",
            "stream_id": 5002,
            "stream_icon": "https://cdn.example.com/inception.jpg",
            "rating": 8.8,
            "added": "1704067200",
            "category_id": "10",
            "container_extension": "mp4",
            "custom_sid": "",
            "direct_source": ""
        }
    ]
    """

    static let vodCategories = """
    [
        {"category_id": "10", "category_name": "Action Movies", "parent_id": 0},
        {"category_id": "11", "category_name": "Comedy", "parent_id": 0}
    ]
    """

    // MARK: - VOD Info

    static let vodInfo = """
    {
        "info": {
            "movie_image": "https://cdn.example.com/matrix_poster.jpg",
            "backdrop_path": ["https://cdn.example.com/matrix_bg1.jpg", "https://cdn.example.com/matrix_bg2.jpg"],
            "tmdb_id": "603",
            "releasedate": "1999-03-31",
            "youtube_trailer": "m8e-FF8MsqU",
            "genre": "Action, Sci-Fi",
            "plot": "A computer hacker learns about the true nature of reality.",
            "cast": "Keanu Reeves, Laurence Fishburne",
            "rating": "8.7",
            "director": "Lana Wachowski",
            "duration": "02:16:17",
            "duration_secs": 8177
        },
        "movie_data": {
            "stream_id": 5001,
            "name": "The Matrix",
            "added": "1704067200",
            "category_id": "10",
            "container_extension": "mkv",
            "custom_sid": "",
            "direct_source": ""
        }
    }
    """

    /// backdrop_path as a single string instead of array.
    static let vodInfoBackdropString = """
    {
        "info": {
            "movie_image": "https://cdn.example.com/poster.jpg",
            "backdrop_path": "https://cdn.example.com/backdrop.jpg",
            "genre": "Drama",
            "plot": "A test plot.",
            "rating": ""
        },
        "movie_data": {
            "stream_id": 9999,
            "name": "Test Movie"
        }
    }
    """

    // MARK: - Series

    static let seriesList = """
    [
        {
            "num": 1,
            "name": "Breaking Bad",
            "series_id": 789,
            "cover": "https://cdn.example.com/bb_poster.jpg",
            "plot": "A high school chemistry teacher turned meth manufacturer.",
            "cast": "Bryan Cranston, Aaron Paul",
            "director": "Vince Gilligan",
            "genre": "Crime, Drama, Thriller",
            "release_date": "2008-01-20",
            "rating": "9.5",
            "category_id": "20",
            "backdrop_path": ["https://cdn.example.com/bb_bg.jpg"]
        }
    ]
    """

    static let seriesCategories = """
    [
        {"category_id": "20", "category_name": "Drama", "parent_id": 0},
        {"category_id": "21", "category_name": "Comedy", "parent_id": 0}
    ]
    """

    // MARK: - Series Info

    static let seriesInfo = """
    {
        "seasons": [
            {
                "season_number": 1,
                "name": "Season 1",
                "air_date": "2008-01-20",
                "episode_count": 7,
                "cover": "https://cdn.example.com/bb_s1.jpg",
                "overview": "The beginning of Walter White's transformation."
            },
            {
                "season_number": 2,
                "name": "Season 2",
                "air_date": "2009-03-08",
                "episode_count": 13,
                "cover": "https://cdn.example.com/bb_s2.jpg",
                "overview": "Walt and Jesse expand their operation."
            }
        ],
        "info": {
            "name": "Breaking Bad",
            "cover": "https://cdn.example.com/bb_poster.jpg",
            "plot": "A high school chemistry teacher turned meth manufacturer.",
            "cast": "Bryan Cranston, Aaron Paul",
            "director": "Vince Gilligan",
            "genre": "Crime, Drama, Thriller",
            "release_date": "2008-01-20",
            "rating": "9.5",
            "backdrop_path": ["https://cdn.example.com/bb_bg.jpg"],
            "category_id": "20"
        },
        "episodes": {
            "1": [
                {
                    "id": "45678",
                    "episode_num": 1,
                    "title": "Pilot",
                    "container_extension": "mkv",
                    "info": {
                        "movie_image": "https://cdn.example.com/bb_s1e1.jpg",
                        "plot": "Walter White, a chemistry teacher, discovers he has cancer.",
                        "releasedate": "2008-01-20",
                        "rating": 8.9,
                        "duration_secs": 3480,
                        "duration": "00:58:00"
                    },
                    "season": 1,
                    "added": "1640995200",
                    "custom_sid": "",
                    "direct_source": ""
                },
                {
                    "id": "45679",
                    "episode_num": 2,
                    "title": "Cat's in the Bag...",
                    "container_extension": "mkv",
                    "info": {
                        "movie_image": "https://cdn.example.com/bb_s1e2.jpg",
                        "plot": "Walt and Jesse try to dispose of the bodies.",
                        "releasedate": "2008-01-27",
                        "rating": 8.5,
                        "duration_secs": 2880,
                        "duration": "00:48:00"
                    },
                    "season": 1,
                    "added": "1640995200",
                    "custom_sid": "",
                    "direct_source": ""
                }
            ],
            "2": [
                {
                    "id": "45690",
                    "episode_num": 1,
                    "title": "Seven Thirty-Seven",
                    "container_extension": "mkv",
                    "info": {
                        "movie_image": "https://cdn.example.com/bb_s2e1.jpg",
                        "plot": "Walt and Jesse face Tuco.",
                        "releasedate": "2009-03-08",
                        "rating": 8.7,
                        "duration_secs": 2820,
                        "duration": "00:47:00"
                    },
                    "season": 2,
                    "added": "1640995200",
                    "custom_sid": "",
                    "direct_source": ""
                }
            ]
        }
    }
    """

    // MARK: - EPG

    static let shortEPG: String = {
        let title = Data("Morning News".utf8).base64EncodedString()
        let desc = Data("Your daily morning news update.".utf8).base64EncodedString()
        let title2 = Data("Sports Center".utf8).base64EncodedString()
        let desc2 = Data("Live sports coverage and highlights.".utf8).base64EncodedString()
        return """
        {
            "epg_listings": [
                {
                    "id": "100",
                    "epg_id": "200",
                    "title": "\(title)",
                    "lang": "en",
                    "start": "2024-03-01 08:00:00",
                    "end": "2024-03-01 09:00:00",
                    "description": "\(desc)",
                    "channel_id": "ESPN.us",
                    "start_timestamp": "1709280000",
                    "stop_timestamp": "1709283600"
                },
                {
                    "id": "101",
                    "epg_id": "200",
                    "title": "\(title2)",
                    "lang": "en",
                    "start": "2024-03-01 09:00:00",
                    "end": "2024-03-01 10:00:00",
                    "description": "\(desc2)",
                    "channel_id": "ESPN.us",
                    "start_timestamp": "1709283600",
                    "stop_timestamp": "1709287200"
                }
            ]
        }
        """
    }()

    static let emptyEPG = """
    {
        "epg_listings": []
    }
    """

    // MARK: - Malformed

    static let malformedJSON = "{ this is not valid json }"

    static let htmlErrorPage = """
    <!DOCTYPE html><html><body><h1>403 Forbidden</h1></body></html>
    """
}

// swiftlint:enable line_length
