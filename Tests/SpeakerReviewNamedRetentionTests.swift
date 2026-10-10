import Foundation

/// Picking "This is me" is a naming. The review card must keep You on
/// screen the same way a typed name or a saved-person chip does, so the
/// named row and the done footer can show.
func testSpeakerReviewNamedRetention() {
    runSuite("This is me keeps You on the review card") {
        let voiceID = UUID()
        let you = SpeakerReviewNamedRetention.thisIsMe(voiceID: voiceID, existingOwner: nil)

        assertEqual(you.name, SpeakerNameSelectionPolicy.ownerLabel, "This is me names the voice You")
        assertEqual(you.voiceID, voiceID)
        assertEqual(you.personID, voiceID, "with no saved You, the voice itself becomes You")
        assertTrue(you.isNewPerson)
        assertEqual(you.confirmedBefore, 0)

        let kept = SpeakerReviewNamedRetention.retainedVoice(
            after: .markedAsMe,
            didSave: true,
            named: you
        )
        assertEqual(kept?.name, SpeakerNameSelectionPolicy.ownerLabel)
        assertEqual(kept?.voiceID, voiceID, "the card holds the same voice the queue just dropped")

        assertNil(
            SpeakerReviewNamedRetention.retainedVoice(after: .markedAsMe, didSave: false, named: you),
            "a failed save must not keep a You row the store never wrote"
        )

        let ownerID = UUID()
        let existingYou = SpeakerReviewNamedRetention.thisIsMe(
            voiceID: voiceID,
            existingOwner: SpeakerReviewNamedRetention.Owner(
                id: ownerID,
                name: SpeakerNameSelectionPolicy.ownerLabel,
                confirmedMeetings: 3,
                requiredMeetings: 5,
                isTrusted: true
            )
        )
        assertFalse(existingYou.isNewPerson, "an existing You is a join, not a second You")
        assertEqual(existingYou.personID, ownerID)
        assertEqual(existingYou.confirmedBefore, 3)
        assertEqual(
            SpeakerReviewNamedRetention.retainedVoice(
                after: .markedAsMe,
                didSave: true,
                named: existingYou
            )?.personID,
            ownerID
        )
    }
}
