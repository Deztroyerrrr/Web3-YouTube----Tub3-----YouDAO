(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-insufficient-funds (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-invalid-input (err u105))
(define-constant err-voting-ended (err u106))

(define-fungible-token tub3-token)

(define-non-fungible-token video-clip uint)

(define-data-var next-video-id uint u1)
(define-data-var next-clip-id uint u1)
(define-data-var next-proposal-id uint u1)
(define-data-var platform-fee-rate uint u500)

(define-map videos
    { video-id: uint }
    {
        creator: principal,
        title: (string-ascii 100),
        ipfs-hash: (string-ascii 100),
        duration: uint,
        upload-block: uint,
        total-views: uint,
        total-revenue: uint,
        status: (string-ascii 20)
    }
)

(define-map user-profiles
    { user: principal }
    {
        username: (string-ascii 50),
        reputation: uint,
        total-earnings: uint,
        videos-created: uint,
        videos-watched: uint
    }
)

(define-map video-clips
    { clip-id: uint }
    {
        video-id: uint,
        owner: principal,
        title: (string-ascii 100),
        start-time: uint,
        end-time: uint,
        mint-block: uint,
        rarity-score: uint
    }
)

(define-map watch-sessions
    { video-id: uint, viewer: principal }
    {
        watch-time: uint,
        completion-rate: uint,
        last-watch-block: uint,
        reward-claimed: bool
    }
)

(define-map ad-campaigns
    { campaign-id: uint }
    {
        advertiser: principal,
        budget: uint,
        per-view-payout: uint,
        target-views: uint,
        current-views: uint,
        active: bool
    }
)

(define-map dao-proposals
    { proposal-id: uint }
    {
        proposer: principal,
        target-video: uint,
        proposal-type: (string-ascii 20),
        description: (string-ascii 200),
        votes-for: uint,
        votes-against: uint,
        voting-deadline: uint,
        executed: bool
    }
)

(define-map dao-votes
    { proposal-id: uint, voter: principal }
    { vote: bool, voting-power: uint }
)

(define-private (is-contract-owner)
    (is-eq tx-sender contract-owner)
)

(define-private (get-user-reputation (user principal))
    (default-to u0 (get reputation (map-get? user-profiles { user: user })))
)

(define-private (calculate-voting-power (user principal))
    (let ((reputation (get-user-reputation user))
          (balance (ft-get-balance tub3-token user)))
        (+ reputation (/ balance u1000))
    )
)

(define-private (distribute-ad-revenue (video-id uint) (amount uint))
    (let ((video-data (unwrap! (map-get? videos { video-id: video-id }) (err u0)))
          (creator (get creator video-data))
          (platform-fee (/ (* amount (var-get platform-fee-rate)) u10000))
          (creator-share (- amount platform-fee)))
        (begin
            (try! (ft-mint? tub3-token creator-share creator))
            (try! (ft-mint? tub3-token platform-fee contract-owner))
            (map-set videos { video-id: video-id }
                (merge video-data { total-revenue: (+ (get total-revenue video-data) amount) }))
            (ok true)
        )
    )
)

(define-public (create-profile (username (string-ascii 50)))
    (let ((user tx-sender))
        (if (is-some (map-get? user-profiles { user: user }))
            err-already-exists
            (ok (map-set user-profiles { user: user }
                {
                    username: username,
                    reputation: u100,
                    total-earnings: u0,
                    videos-created: u0,
                    videos-watched: u0
                }
            ))
        )
    )
)

(define-public (upload-video (title (string-ascii 100)) (ipfs-hash (string-ascii 100)) (duration uint))
    (let ((video-id (var-get next-video-id))
          (creator tx-sender))
        (asserts! (> (len title) u0) err-invalid-input)
        (asserts! (> (len ipfs-hash) u0) err-invalid-input)
        (asserts! (> duration u0) err-invalid-input)
        
        (map-set videos { video-id: video-id }
            {
                creator: creator,
                title: title,
                ipfs-hash: ipfs-hash,
                duration: duration,
                upload-block: stacks-block-height,
                total-views: u0,
                total-revenue: u0,
                status: "active"
            }
        )
        
        (let ((profile (default-to 
                { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                (map-get? user-profiles { user: creator }))))
            (map-set user-profiles { user: creator }
                (merge profile { videos-created: (+ (get videos-created profile) u1) }))
        )
        
        (var-set next-video-id (+ video-id u1))
        (ok video-id)
    )
)

(define-public (watch-video (video-id uint) (watch-duration uint))
    (let ((video-data (unwrap! (map-get? videos { video-id: video-id }) err-not-found))
          (viewer tx-sender)
          (completion-rate (/ (* watch-duration u100) (get duration video-data))))
        
        (asserts! (is-eq (get status video-data) "active") err-unauthorized)
        (asserts! (> watch-duration u0) err-invalid-input)
        
        (map-set watch-sessions { video-id: video-id, viewer: viewer }
            {
                watch-time: watch-duration,
                completion-rate: completion-rate,
                last-watch-block: stacks-block-height,
                reward-claimed: false
            }
        )
        
        (map-set videos { video-id: video-id }
            (merge video-data { total-views: (+ (get total-views video-data) u1) }))
        
        (let ((profile (default-to 
                { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                (map-get? user-profiles { user: viewer }))))
            (map-set user-profiles { user: viewer }
                (merge profile { videos-watched: (+ (get videos-watched profile) u1) }))
        )
        
        (ok completion-rate)
    )
)

(define-public (claim-watch-reward (video-id uint))
    (let ((session (unwrap! (map-get? watch-sessions { video-id: video-id, viewer: tx-sender }) err-not-found))
          (completion-rate (get completion-rate session)))
        
        (asserts! (not (get reward-claimed session)) err-unauthorized)
        (asserts! (>= completion-rate u50) err-unauthorized)
        
        (let ((reward-amount (* completion-rate u10)))
            (try! (ft-mint? tub3-token reward-amount tx-sender))
            
            (map-set watch-sessions { video-id: video-id, viewer: tx-sender }
                (merge session { reward-claimed: true }))
            
            (let ((profile (default-to 
                    { username: "", reputation: u100, total-earnings: u0, videos-created: u0, videos-watched: u0 }
                    (map-get? user-profiles { user: tx-sender }))))
                (map-set user-profiles { user: tx-sender }
                    (merge profile { 
                        total-earnings: (+ (get total-earnings profile) reward-amount),
                        reputation: (+ (get reputation profile) u1)
                    }))
            )
            
            (ok reward-amount)
        )
    )
)

(define-public (mint-video-clip (video-id uint) (title (string-ascii 100)) (start-time uint) (end-time uint))
    (let ((clip-id (var-get next-clip-id))
          (video-data (unwrap! (map-get? videos { video-id: video-id }) err-not-found))
          (rarity-score (+ (get total-views video-data) (* (- end-time start-time) u100))))
        
        (asserts! (is-eq (get status video-data) "active") err-unauthorized)
        (asserts! (< start-time end-time) err-invalid-input)
        (asserts! (<= end-time (get duration video-data)) err-invalid-input)
        
        (try! (nft-mint? video-clip clip-id tx-sender))
        
        (map-set video-clips { clip-id: clip-id }
            {
                video-id: video-id,
                owner: tx-sender,
                title: title,
                start-time: start-time,
                end-time: end-time,
                mint-block: stacks-block-height,
                rarity-score: rarity-score
            }
        )
        
        (var-set next-clip-id (+ clip-id u1))
        (ok clip-id)
    )
)

(define-public (create-dao-proposal (target-video uint) (proposal-type (string-ascii 20)) (description (string-ascii 200)))
    (let ((proposal-id (var-get next-proposal-id))
          (voting-power (calculate-voting-power tx-sender)))
        
        (asserts! (>= voting-power u10) err-unauthorized)
        (asserts! (is-some (map-get? videos { video-id: target-video })) err-not-found)
        
        (map-set dao-proposals { proposal-id: proposal-id }
            {
                proposer: tx-sender,
                target-video: target-video,
                proposal-type: proposal-type,
                description: description,
                votes-for: u0,
                votes-against: u0,
                voting-deadline: (+ stacks-block-height u1440),
                executed: false
            }
        )
        
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

(define-public (vote-on-proposal (proposal-id uint) (support bool))
    (let ((proposal (unwrap! (map-get? dao-proposals { proposal-id: proposal-id }) err-not-found))
          (voting-power (calculate-voting-power tx-sender)))
        
        (asserts! (< stacks-block-height (get voting-deadline proposal)) err-voting-ended)
        (asserts! (is-none (map-get? dao-votes { proposal-id: proposal-id, voter: tx-sender })) err-already-exists)
        (asserts! (> voting-power u0) err-unauthorized)
        
        (map-set dao-votes { proposal-id: proposal-id, voter: tx-sender }
            { vote: support, voting-power: voting-power })
        
        (let ((updated-proposal
                (if support
                    (merge proposal { votes-for: (+ (get votes-for proposal) voting-power) })
                    (merge proposal { votes-against: (+ (get votes-against proposal) voting-power) }))))
            (map-set dao-proposals { proposal-id: proposal-id } updated-proposal)
        )
        
        (ok true)
    )
)

(define-public (execute-proposal (proposal-id uint))
    (let ((proposal (unwrap! (map-get? dao-proposals { proposal-id: proposal-id }) err-not-found)))
        
        (asserts! (>= stacks-block-height (get voting-deadline proposal)) err-voting-ended)
        (asserts! (not (get executed proposal)) err-already-exists)
        (asserts! (> (get votes-for proposal) (get votes-against proposal)) err-unauthorized)
        
        (begin
            (if (is-eq (get proposal-type proposal) "remove")
                (let ((video-data (unwrap! (map-get? videos { video-id: (get target-video proposal) }) err-not-found)))
                    (map-set videos { video-id: (get target-video proposal) }
                        (merge video-data { status: "removed" }))
                )
                true
            )
            
            (map-set dao-proposals { proposal-id: proposal-id }
                (merge proposal { executed: true }))
            
            (ok true)
        )
    )
)

(define-read-only (get-video (video-id uint))
    (map-get? videos { video-id: video-id })
)

(define-read-only (get-user-profile (user principal))
    (map-get? user-profiles { user: user })
)

(define-read-only (get-video-clip (clip-id uint))
    (map-get? video-clips { clip-id: clip-id })
)

(define-read-only (get-watch-session (video-id uint) (viewer principal))
    (map-get? watch-sessions { video-id: video-id, viewer: viewer })
)

(define-read-only (get-dao-proposal (proposal-id uint))
    (map-get? dao-proposals { proposal-id: proposal-id })
)

(define-read-only (get-user-vote (proposal-id uint) (voter principal))
    (map-get? dao-votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-total-supply)
    (ft-get-supply tub3-token)
)

(define-read-only (get-balance (user principal))
    (ft-get-balance tub3-token user)
)
